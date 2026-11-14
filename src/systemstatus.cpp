// SPDX-License-Identifier: GPL-3.0-or-later
#include "systemstatus.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QSysInfo>

#include <pwd.h>
#include <unistd.h>

static SystemStatus *s_sys = nullptr;

static QString readFile(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(f.readAll()).trimmed();
}

static bool hasProgram(const char *name)
{
    return !QStandardPaths::findExecutable(QString::fromLatin1(name)).isEmpty();
}

SystemStatus::SystemStatus(QObject *parent)
    : QObject(parent)
{
    const auto backlights = QDir(QStringLiteral("/sys/class/backlight")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    if (!backlights.isEmpty())
        m_backlight = backlights.first();
    m_poll.setInterval(4000);
    connect(&m_poll, &QTimer::timeout, this, &SystemStatus::refresh);
    m_poll.start();
    QTimer::singleShot(0, this, &SystemStatus::refresh);
}

SystemStatus *SystemStatus::instance()
{
    if (!s_sys)
        s_sys = new SystemStatus;
    return s_sys;
}

SystemStatus *SystemStatus::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

void SystemStatus::refresh()
{
    readBattery();
    readNetwork();
    readVolume();
    readBrightness();
}

void SystemStatus::readBattery()
{
    bool has = false;
    int level = 100;
    bool charging = false;
    const QDir dir(QStringLiteral("/sys/class/power_supply"));
    for (const QString &name : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System)) {
        const QString base = dir.filePath(name);
        if (readFile(base + QStringLiteral("/type")) != QLatin1String("Battery"))
            continue;
        if (readFile(base + QStringLiteral("/scope")) == QLatin1String("Device"))
            continue; // peripherals (mice, headsets)
        has = true;
        level = readFile(base + QStringLiteral("/capacity")).toInt();
        const QString status = readFile(base + QStringLiteral("/status"));
        charging = status == QLatin1String("Charging") || status == QLatin1String("Full");
        break;
    }
    if (has != m_hasBattery || level != m_batteryLevel || charging != m_charging) {
        m_hasBattery = has;
        m_batteryLevel = level;
        m_charging = charging;
        Q_EMIT batteryChanged();
    }
}

void SystemStatus::readNetwork()
{
    QString type = QStringLiteral("none");
    bool hasWifi = false;
    QString wifiIface;
    const QDir dir(QStringLiteral("/sys/class/net"));
    for (const QString &iface : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System)) {
        if (iface == QLatin1String("lo"))
            continue;
        const QString base = dir.filePath(iface);
        const bool wireless = QFileInfo::exists(base + QStringLiteral("/wireless"))
            || QFileInfo::exists(base + QStringLiteral("/phy80211"));
        if (wireless) {
            hasWifi = true;
            wifiIface = iface;
        }
        // Skip virtual bridges/containers unless nothing else is up.
        const bool isVirtual = QFileInfo(base).symLinkTarget().contains(QLatin1String("/virtual/"));
        const QString state = readFile(base + QStringLiteral("/operstate"));
        const bool up = state == QLatin1String("up") || (state == QLatin1String("unknown") && readFile(base + QStringLiteral("/carrier")) == QLatin1String("1"));
        if (!up)
            continue;
        if (wireless)
            type = QStringLiteral("wifi");
        else if (type == QLatin1String("none") || (type == QLatin1String("virtual") && !isVirtual))
            type = isVirtual ? QStringLiteral("virtual") : QStringLiteral("wired");
    }
    if (type == QLatin1String("virtual"))
        type = QStringLiteral("wired");

    bool changed = type != m_networkType || hasWifi != m_hasWifi;
    m_networkType = type;
    m_hasWifi = hasWifi;

    if (hasProgram("nmcli")) {
        auto *p = new QProcess(this);
        connect(p, &QProcess::finished, this, [this, p] {
            const QStringList lines = QString::fromUtf8(p->readAllStandardOutput()).split(QLatin1Char('\n'));
            QString ssid;
            bool radio = m_wifiEnabled;
            for (const QString &l : lines) {
                if (l.startsWith(QLatin1String("RADIO:")))
                    radio = l.mid(6).trimmed() == QLatin1String("enabled");
                else if (l.startsWith(QLatin1String("yes:")))
                    ssid = l.mid(4);
            }
            if (ssid != m_networkName || radio != m_wifiEnabled) {
                m_networkName = ssid;
                m_wifiEnabled = radio;
                Q_EMIT networkChanged();
            }
            p->deleteLater();
        });
        p->start(QStringLiteral("sh"), {QStringLiteral("-c"),
                 QStringLiteral("echo RADIO:$(nmcli radio wifi 2>/dev/null); nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes:'")});
    } else if (m_wifiEnabled != hasWifi) {
        m_wifiEnabled = hasWifi;
        changed = true;
    }
    if (changed)
        Q_EMIT networkChanged();
}

void SystemStatus::readVolume()
{
    if (m_volumeBusy)
        return;
    QString program;
    QStringList args;
    if (hasProgram("wpctl")) {
        program = QStringLiteral("wpctl");
        args = {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")};
    } else if (hasProgram("pactl")) {
        program = QStringLiteral("sh");
        args = {QStringLiteral("-c"), QStringLiteral("pactl get-sink-volume @DEFAULT_SINK@; pactl get-sink-mute @DEFAULT_SINK@")};
    } else {
        return;
    }
    m_volumeBusy = true;
    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [this, p, program](int code) {
        m_volumeBusy = false;
        const QString out = QString::fromUtf8(p->readAllStandardOutput());
        p->deleteLater();
        bool has = code == 0 && !out.isEmpty();
        int vol = m_volume;
        bool muted = m_muted;
        if (has && program == QLatin1String("wpctl")) {
            static const QRegularExpression re(QStringLiteral("Volume:\\s*([0-9.]+)"));
            const auto m = re.match(out);
            if (m.hasMatch())
                vol = qRound(m.captured(1).toDouble() * 100);
            muted = out.contains(QLatin1String("MUTED"));
        } else if (has) {
            static const QRegularExpression re(QStringLiteral("(\\d+)%"));
            const auto m = re.match(out);
            if (m.hasMatch())
                vol = m.captured(1).toInt();
            muted = out.contains(QLatin1String("Mute: yes"));
        }
        if (has != m_hasAudio || vol != m_volume || muted != m_muted) {
            m_hasAudio = has;
            m_volume = vol;
            m_muted = muted;
            Q_EMIT volumeChanged();
        }
    });
    p->start(program, args);
}

void SystemStatus::setVolume(int percent)
{
    percent = qBound(0, percent, 150);
    m_volume = percent;
    Q_EMIT volumeChanged();
    if (hasProgram("wpctl"))
        QProcess::startDetached(QStringLiteral("wpctl"), {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QString::number(percent / 100.0)});
    else if (hasProgram("pactl"))
        QProcess::startDetached(QStringLiteral("pactl"), {QStringLiteral("set-sink-volume"), QStringLiteral("@DEFAULT_SINK@"), QString::number(percent) + QLatin1Char('%')});
}

void SystemStatus::toggleMute()
{
    m_muted = !m_muted;
    Q_EMIT volumeChanged();
    if (hasProgram("wpctl"))
        QProcess::startDetached(QStringLiteral("wpctl"), {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QStringLiteral("toggle")});
    else if (hasProgram("pactl"))
        QProcess::startDetached(QStringLiteral("pactl"), {QStringLiteral("set-sink-mute"), QStringLiteral("@DEFAULT_SINK@"), QStringLiteral("toggle")});
}

void SystemStatus::readBrightness()
{
    if (m_backlight.isEmpty())
        return;
    const QString base = QStringLiteral("/sys/class/backlight/") + m_backlight;
    const int max = readFile(base + QStringLiteral("/max_brightness")).toInt();
    const int cur = readFile(base + QStringLiteral("/brightness")).toInt();
    if (max <= 0)
        return;
    const int pct = qRound(cur * 100.0 / max);
    if (pct != m_brightness) {
        m_brightness = pct;
        Q_EMIT brightnessChanged();
    }
}

void SystemStatus::setBrightness(int percent)
{
    if (m_backlight.isEmpty())
        return;
    percent = qBound(5, percent, 100);
    m_brightness = percent;
    Q_EMIT brightnessChanged();
    const QString base = QStringLiteral("/sys/class/backlight/") + m_backlight;
    const int max = readFile(base + QStringLiteral("/max_brightness")).toInt();
    const uint value = uint(qRound(max * percent / 100.0));
    // logind lets the session owner set the backlight without root.
    QDBusInterface session(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1/session/auto"),
                           QStringLiteral("org.freedesktop.login1.Session"), QDBusConnection::systemBus());
    if (session.isValid()) {
        session.asyncCall(QStringLiteral("SetBrightness"), QStringLiteral("backlight"), m_backlight, value);
        return;
    }
    if (hasProgram("brightnessctl"))
        QProcess::startDetached(QStringLiteral("brightnessctl"), {QStringLiteral("set"), QString::number(percent) + QLatin1Char('%')});
}

void SystemStatus::setWifiEnabled(bool on)
{
    m_wifiEnabled = on;
    Q_EMIT networkChanged();
    if (hasProgram("nmcli"))
        QProcess::startDetached(QStringLiteral("nmcli"), {QStringLiteral("radio"), QStringLiteral("wifi"), on ? QStringLiteral("on") : QStringLiteral("off")});
}

QString SystemStatus::userName() const
{
    if (const passwd *pw = getpwuid(getuid()))
        return QString::fromLocal8Bit(pw->pw_name);
    return qEnvironmentVariable("USER");
}

QString SystemStatus::realName() const
{
    if (const passwd *pw = getpwuid(getuid())) {
        const QString gecos = QString::fromLocal8Bit(pw->pw_gecos).section(QLatin1Char(','), 0, 0).trimmed();
        if (!gecos.isEmpty())
            return gecos;
    }
    QString n = userName();
    if (!n.isEmpty())
        n[0] = n[0].toUpper();
    return n;
}

QString SystemStatus::hostName() const { return QSysInfo::machineHostName(); }

QString SystemStatus::avatar() const
{
    const QStringList candidates = {
        QDir::homePath() + QStringLiteral("/.face"),
        QDir::homePath() + QStringLiteral("/.face.icon"),
        QStringLiteral("/var/lib/AccountsService/icons/") + userName(),
    };
    for (const QString &c : candidates)
        if (QFileInfo(c).isReadable() && QFileInfo(c).size() > 0)
            return QUrl::fromLocalFile(c).toString();
    return {};
}

QString SystemStatus::kernel() const { return QSysInfo::kernelType() + QLatin1Char(' ') + QSysInfo::kernelVersion(); }
QString SystemStatus::osName() const { return QSysInfo::prettyProductName(); }

QString SystemStatus::cpuModel() const
{
    const QString info = readFile(QStringLiteral("/proc/cpuinfo"));
    for (const QString &line : info.split(QLatin1Char('\n')))
        if (line.startsWith(QLatin1String("model name")))
            return line.section(QLatin1Char(':'), 1).trimmed();
    return QSysInfo::currentCpuArchitecture();
}

QString SystemStatus::memoryTotal() const
{
    const QString info = readFile(QStringLiteral("/proc/meminfo"));
    static const QRegularExpression re(QStringLiteral("MemTotal:\\s+(\\d+)"));
    const auto m = re.match(info);
    if (!m.hasMatch())
        return {};
    return QString::number(m.captured(1).toDouble() / 1024.0 / 1024.0, 'f', 1) + QStringLiteral(" GB");
}

bool SystemStatus::logindCall(const QString &method)
{
    QDBusInterface mgr(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"),
                       QStringLiteral("org.freedesktop.login1.Manager"), QDBusConnection::systemBus());
    if (!mgr.isValid())
        return false;
    const QDBusMessage reply = mgr.call(method, false);
    return reply.type() != QDBusMessage::ErrorMessage;
}

void SystemStatus::powerOff()
{
    if (!logindCall(QStringLiteral("PowerOff")))
        QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("poweroff")});
}

void SystemStatus::reboot()
{
    if (!logindCall(QStringLiteral("Reboot")))
        QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("reboot")});
}

void SystemStatus::suspend()
{
    if (!logindCall(QStringLiteral("Suspend")))
        QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("suspend")});
}

void SystemStatus::hibernate()
{
    if (!logindCall(QStringLiteral("Hibernate")))
        QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("hibernate")});
}

bool SystemStatus::canSuspend() const
{
    QDBusInterface mgr(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"),
                       QStringLiteral("org.freedesktop.login1.Manager"), QDBusConnection::systemBus());
    if (!mgr.isValid())
        return false;
    QDBusReply<QString> r = mgr.call(QStringLiteral("CanSuspend"));
    return r.isValid() && r.value() == QLatin1String("yes");
}
