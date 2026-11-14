// SPDX-License-Identifier: GPL-3.0-or-later
#include "desktopentry.h"

#include <QFile>
#include <QFileInfo>
#include <QLocale>

namespace {
QString g_localeOverride;

QStringList localeCandidates()
{
    // lang_COUNTRY@MODIFIER, lang_COUNTRY, lang@MODIFIER, lang
    QString loc = g_localeOverride.isEmpty() ? QLocale::system().name() : g_localeOverride;
    QString modifier;
    const int at = loc.indexOf(QLatin1Char('@'));
    if (at >= 0) {
        modifier = loc.mid(at + 1);
        loc = loc.left(at);
    }
    const int dot = loc.indexOf(QLatin1Char('.'));
    if (dot >= 0)
        loc = loc.left(dot);
    const QString lang = loc.section(QLatin1Char('_'), 0, 0);
    const bool hasCountry = loc.contains(QLatin1Char('_'));

    QStringList out;
    if (!modifier.isEmpty() && hasCountry)
        out << loc + QLatin1Char('@') + modifier;
    if (hasCountry)
        out << loc;
    if (!modifier.isEmpty())
        out << lang + QLatin1Char('@') + modifier;
    out << lang;
    return out;
}
} // namespace

void DesktopEntry::setLocaleOverride(const QString &locale)
{
    g_localeOverride = locale;
}

DesktopEntry DesktopEntry::fromFile(const QString &path, const QString &desktopId)
{
    DesktopEntry e;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return e;
    e.m_path = path;
    e.m_desktopId = desktopId.isEmpty() ? QFileInfo(path).fileName() : desktopId;
    e.parse(f.readAll());
    return e;
}

DesktopEntry DesktopEntry::fromData(const QByteArray &data, const QString &desktopId)
{
    DesktopEntry e;
    e.m_desktopId = desktopId;
    e.parse(data);
    return e;
}

void DesktopEntry::parse(const QByteArray &data)
{
    QString group;
    const QStringList lines = QString::fromUtf8(data).split(QLatin1Char('\n'));
    for (QString line : lines) {
        line = line.trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#')))
            continue;
        if (line.startsWith(QLatin1Char('[')) && line.endsWith(QLatin1Char(']'))) {
            group = line.mid(1, line.size() - 2);
            continue;
        }
        if (group.isEmpty())
            continue;
        const int eq = line.indexOf(QLatin1Char('='));
        if (eq <= 0)
            continue;
        const QString key = line.left(eq).trimmed();
        const QString val = line.mid(eq + 1).trimmed();
        auto &g = m_groups[group];
        if (!g.contains(key)) // first occurrence wins
            g.insert(key, val);
    }
    m_valid = m_groups.contains(QStringLiteral("Desktop Entry"))
        && !value(QStringLiteral("Type")).isEmpty();
}

QString DesktopEntry::value(const QString &key, const QString &group) const
{
    const auto g = m_groups.constFind(group);
    if (g == m_groups.constEnd())
        return {};
    return unescape(g->value(key));
}

QString DesktopEntry::localized(const QString &key) const
{
    const auto g = m_groups.constFind(QStringLiteral("Desktop Entry"));
    if (g == m_groups.constEnd())
        return {};
    for (const QString &loc : localeCandidates()) {
        const QString k = key + QLatin1Char('[') + loc + QLatin1Char(']');
        if (g->contains(k))
            return unescape(g->value(k));
    }
    return unescape(g->value(key));
}

QStringList DesktopEntry::list(const QString &key) const
{
    const auto g = m_groups.constFind(QStringLiteral("Desktop Entry"));
    if (g == m_groups.constEnd())
        return {};
    return splitList(g->value(key));
}

QStringList DesktopEntry::keywords() const
{
    const auto g = m_groups.constFind(QStringLiteral("Desktop Entry"));
    if (g == m_groups.constEnd())
        return {};
    for (const QString &loc : localeCandidates()) {
        const QString k = QStringLiteral("Keywords[") + loc + QLatin1Char(']');
        if (g->contains(k))
            return splitList(g->value(k));
    }
    return splitList(g->value(QStringLiteral("Keywords")));
}

bool DesktopEntry::boolValue(const QString &key) const
{
    return value(key).compare(QLatin1String("true"), Qt::CaseInsensitive) == 0;
}

bool DesktopEntry::isVisibleIn(const QString &desktop) const
{
    if (!m_valid || hidden() || noDisplay())
        return false;
    if (type() != QLatin1String("Application"))
        return false;
    const QStringList desktops = desktop.split(QLatin1Char(':'), Qt::SkipEmptyParts);
    const QStringList only = onlyShowIn();
    if (!only.isEmpty()) {
        bool match = false;
        for (const QString &d : desktops)
            match = match || only.contains(d, Qt::CaseInsensitive);
        if (!match)
            return false;
    }
    for (const QString &d : desktops)
        if (notShowIn().contains(d, Qt::CaseInsensitive))
            return false;
    return !exec().isEmpty();
}

QStringList DesktopEntry::splitList(const QString &value)
{
    QStringList out;
    QString cur;
    for (int i = 0; i < value.size(); ++i) {
        const QChar c = value.at(i);
        if (c == QLatin1Char('\\') && i + 1 < value.size() && value.at(i + 1) == QLatin1Char(';')) {
            cur += QLatin1Char(';');
            ++i;
        } else if (c == QLatin1Char(';')) {
            if (!cur.trimmed().isEmpty())
                out << unescape(cur.trimmed());
            cur.clear();
        } else {
            cur += c;
        }
    }
    if (!cur.trimmed().isEmpty())
        out << unescape(cur.trimmed());
    return out;
}

QString DesktopEntry::unescape(const QString &value)
{
    if (!value.contains(QLatin1Char('\\')))
        return value;
    QString out;
    out.reserve(value.size());
    for (int i = 0; i < value.size(); ++i) {
        const QChar c = value.at(i);
        if (c != QLatin1Char('\\') || i + 1 >= value.size()) {
            out += c;
            continue;
        }
        const QChar n = value.at(++i);
        switch (n.unicode()) {
        case 's': out += QLatin1Char(' '); break;
        case 'n': out += QLatin1Char('\n'); break;
        case 't': out += QLatin1Char('\t'); break;
        case 'r': out += QLatin1Char('\r'); break;
        case '\\': out += QLatin1Char('\\'); break;
        default: out += QLatin1Char('\\'); out += n; break;
        }
    }
    return out;
}

QStringList DesktopEntry::tokenizeExec(const QString &exec, bool *ok)
{
    QStringList args;
    QString cur;
    bool inQuotes = false;
    bool hasToken = false;
    for (int i = 0; i < exec.size(); ++i) {
        const QChar c = exec.at(i);
        if (inQuotes) {
            if (c == QLatin1Char('\\') && i + 1 < exec.size()) {
                const QChar n = exec.at(i + 1);
                if (n == QLatin1Char('"') || n == QLatin1Char('`') || n == QLatin1Char('$') || n == QLatin1Char('\\')) {
                    cur += n;
                    ++i;
                    continue;
                }
            }
            if (c == QLatin1Char('"')) {
                inQuotes = false;
                continue;
            }
            cur += c;
        } else if (c == QLatin1Char('"')) {
            inQuotes = true;
            hasToken = true;
        } else if (c.isSpace()) {
            if (hasToken || !cur.isEmpty())
                args << cur;
            cur.clear();
            hasToken = false;
        } else {
            cur += c;
        }
    }
    if (hasToken || !cur.isEmpty())
        args << cur;
    if (ok)
        *ok = !inQuotes;
    return args;
}

QStringList DesktopEntry::execArgs(const QStringList &files) const
{
    bool ok = true;
    const QStringList tokens = tokenizeExec(exec(), &ok);
    if (!ok)
        return {};

    QStringList out;
    bool filesUsed = false;
    for (const QString &tok : tokens) {
        // Whole-argument field codes that expand to multiple args.
        if (tok == QLatin1String("%F") || tok == QLatin1String("%U")) {
            out << files;
            filesUsed = true;
            continue;
        }
        if (tok == QLatin1String("%i")) {
            if (!icon().isEmpty())
                out << QStringLiteral("--icon") << icon();
            continue;
        }
        QString arg;
        bool drop = false;
        for (int i = 0; i < tok.size(); ++i) {
            const QChar c = tok.at(i);
            if (c != QLatin1Char('%') || i + 1 >= tok.size()) {
                arg += c;
                continue;
            }
            const QChar code = tok.at(++i);
            switch (code.unicode()) {
            case '%': arg += QLatin1Char('%'); break;
            case 'f':
            case 'u':
                if (!files.isEmpty() && !filesUsed) {
                    arg += files.first();
                    filesUsed = true;
                } else if (tok.size() == 2) {
                    drop = true;
                }
                break;
            case 'c': arg += name(); break;
            case 'k': arg += m_path; break;
            default: // deprecated/unknown codes (%d %D %n %N %v %m ...) are removed
                if (tok.size() == 2)
                    drop = true;
                break;
            }
        }
        if (!drop)
            out << arg;
    }
    return out;
}
