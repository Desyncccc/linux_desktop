// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QTimer>

// Battery, audio, network, backlight, user and power management.
class SystemStatus : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Sys)
    QML_SINGLETON

    Q_PROPERTY(bool hasBattery READ hasBattery NOTIFY batteryChanged)
    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY batteryChanged)
    Q_PROPERTY(bool charging READ charging NOTIFY batteryChanged)
    Q_PROPERTY(bool hasAudio READ hasAudio NOTIFY volumeChanged)
    Q_PROPERTY(int volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY volumeChanged)
    Q_PROPERTY(QString networkType READ networkType NOTIFY networkChanged)
    Q_PROPERTY(QString networkName READ networkName NOTIFY networkChanged)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY networkChanged)
    Q_PROPERTY(bool hasWifi READ hasWifi NOTIFY networkChanged)
    Q_PROPERTY(bool hasBacklight READ hasBacklight CONSTANT)
    Q_PROPERTY(int brightness READ brightness NOTIFY brightnessChanged)
    Q_PROPERTY(QString userName READ userName CONSTANT)
    Q_PROPERTY(QString realName READ realName CONSTANT)
    Q_PROPERTY(QString hostName READ hostName CONSTANT)
    Q_PROPERTY(QString avatar READ avatar CONSTANT)
    Q_PROPERTY(QString kernel READ kernel CONSTANT)
    Q_PROPERTY(QString osName READ osName CONSTANT)
    Q_PROPERTY(QString cpuModel READ cpuModel CONSTANT)
    Q_PROPERTY(QString memoryTotal READ memoryTotal CONSTANT)

public:
    static SystemStatus *instance();
    static SystemStatus *create(QQmlEngine *, QJSEngine *);

    bool hasBattery() const { return m_hasBattery; }
    int batteryLevel() const { return m_batteryLevel; }
    bool charging() const { return m_charging; }
    bool hasAudio() const { return m_hasAudio; }
    int volume() const { return m_volume; }
    bool muted() const { return m_muted; }
    QString networkType() const { return m_networkType; }
    QString networkName() const { return m_networkName; }
    bool wifiEnabled() const { return m_wifiEnabled; }
    bool hasWifi() const { return m_hasWifi; }
    bool hasBacklight() const { return !m_backlight.isEmpty(); }
    int brightness() const { return m_brightness; }
    QString userName() const;
    QString realName() const;
    QString hostName() const;
    QString avatar() const;
    QString kernel() const;
    QString osName() const;
    QString cpuModel() const;
    QString memoryTotal() const;

    Q_INVOKABLE void setVolume(int percent);
    Q_INVOKABLE void toggleMute();
    Q_INVOKABLE void setBrightness(int percent);
    Q_INVOKABLE void setWifiEnabled(bool on);
    Q_INVOKABLE void refresh();

    Q_INVOKABLE void powerOff();
    Q_INVOKABLE void reboot();
    Q_INVOKABLE void suspend();
    Q_INVOKABLE void hibernate();
    Q_INVOKABLE bool canSuspend() const;

Q_SIGNALS:
    void batteryChanged();
    void volumeChanged();
    void networkChanged();
    void brightnessChanged();

private:
    explicit SystemStatus(QObject *parent = nullptr);
    void readBattery();
    void readNetwork();
    void readVolume();
    void readBrightness();
    bool logindCall(const QString &method);

    QTimer m_poll;
    bool m_hasBattery = false;
    int m_batteryLevel = 100;
    bool m_charging = false;
    bool m_hasAudio = false;
    int m_volume = 0;
    bool m_muted = false;
    QString m_networkType = QStringLiteral("none");
    QString m_networkName;
    bool m_wifiEnabled = false;
    bool m_hasWifi = false;
    QString m_backlight;
    int m_brightness = 100;
    bool m_volumeBusy = false;
};
