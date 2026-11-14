// SPDX-License-Identifier: GPL-3.0-or-later
#include "desktopentry.h"

#include <QTest>

class TestDesktopEntry : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase() { DesktopEntry::setLocaleOverride(QStringLiteral("de_DE")); }

    void parsesBasicKeys()
    {
        const auto e = DesktopEntry::fromData(
            "# comment\n[Desktop Entry]\nType=Application\nName=Text Editor\nName[de]=Texteditor\n"
            "Exec=gedit %U\nIcon=accessories-text-editor\nCategories=Utility;TextEditor;\n"
            "Keywords=text;edit\\;plain;\n\n[Desktop Action new-window]\nName=New Window\nExec=gedit --new-window\n",
            QStringLiteral("org.gnome.gedit.desktop"));
        QVERIFY(e.isValid());
        QCOMPARE(e.type(), QStringLiteral("Application"));
        QCOMPARE(e.name(), QStringLiteral("Texteditor"));
        QCOMPARE(e.icon(), QStringLiteral("accessories-text-editor"));
        QCOMPARE(e.categories(), QStringList({QStringLiteral("Utility"), QStringLiteral("TextEditor")}));
        QCOMPARE(e.keywords(), QStringList({QStringLiteral("text"), QStringLiteral("edit;plain")}));
        QCOMPARE(e.value(QStringLiteral("Exec"), QStringLiteral("Desktop Action new-window")), QStringLiteral("gedit --new-window"));
    }

    void localeFallback()
    {
        DesktopEntry::setLocaleOverride(QStringLiteral("sr_RS@latin"));
        const auto e = DesktopEntry::fromData("[Desktop Entry]\nType=Application\nName=A\nName[sr@latin]=B\nName[sr]=C\n");
        QCOMPARE(e.name(), QStringLiteral("B"));
        DesktopEntry::setLocaleOverride(QStringLiteral("sr_RS"));
        QCOMPARE(e.name(), QStringLiteral("C"));
        DesktopEntry::setLocaleOverride(QStringLiteral("en_US"));
        QCOMPARE(e.name(), QStringLiteral("A"));
        DesktopEntry::setLocaleOverride(QStringLiteral("de_DE"));
    }

    void invalidWithoutType()
    {
        QVERIFY(!DesktopEntry::fromData("[Desktop Entry]\nName=Foo\n").isValid());
        QVERIFY(!DesktopEntry::fromData("Name=Foo\n").isValid());
    }

    void unescape()
    {
        QCOMPARE(DesktopEntry::unescape(QStringLiteral("a\\sb\\nc\\\\d")), QStringLiteral("a b\nc\\d"));
    }

    void tokenizeExec_data()
    {
        QTest::addColumn<QString>("exec");
        QTest::addColumn<QStringList>("args");
        QTest::newRow("simple") << "foo --bar baz" << QStringList{"foo", "--bar", "baz"};
        QTest::newRow("quoted") << "\"/opt/My App/run\" -x" << QStringList{"/opt/My App/run", "-x"};
        QTest::newRow("escaped") << "sh -c \"echo \\\"hi\\\" \\$HOME\"" << QStringList{"sh", "-c", "echo \"hi\" $HOME"};
        QTest::newRow("empty-quoted") << "foo \"\"" << QStringList{"foo", ""};
        QTest::newRow("spaces") << "  foo   bar  " << QStringList{"foo", "bar"};
    }

    void tokenizeExec()
    {
        QFETCH(QString, exec);
        QFETCH(QStringList, args);
        bool ok = false;
        QCOMPARE(DesktopEntry::tokenizeExec(exec, &ok), args);
        QVERIFY(ok);
    }

    void unterminatedQuoteFails()
    {
        bool ok = true;
        DesktopEntry::tokenizeExec(QStringLiteral("foo \"bar"), &ok);
        QVERIFY(!ok);
        const auto e = DesktopEntry::fromData("[Desktop Entry]\nType=Application\nName=X\nExec=foo \"bar\n");
        QVERIFY(e.execArgs().isEmpty());
    }

    void fieldCodes()
    {
        const auto e = DesktopEntry::fromData(
            "[Desktop Entry]\nType=Application\nName=Viewer\nIcon=viewer\nExec=viewer %i --title=%c %F %% %d\n");
        QCOMPARE(e.execArgs({QStringLiteral("/a.png"), QStringLiteral("/b.png")}),
                 QStringList({"viewer", "--icon", "viewer", "--title=Viewer", "/a.png", "/b.png", "%"}));
        QCOMPARE(e.execArgs(), QStringList({"viewer", "--icon", "viewer", "--title=Viewer", "%"}));

        const auto single = DesktopEntry::fromData("[Desktop Entry]\nType=Application\nName=S\nExec=s --open=%u %f\n");
        QCOMPARE(single.execArgs({QStringLiteral("x")}), QStringList({"s", "--open=x"}));
        QCOMPARE(single.execArgs(), QStringList({"s", "--open="}));
    }

    void visibility()
    {
        const auto hidden = DesktopEntry::fromData("[Desktop Entry]\nType=Application\nName=H\nExec=h\nNoDisplay=true\n");
        QVERIFY(!hidden.isVisibleIn(QStringLiteral("Vitrum")));
        const auto only = DesktopEntry::fromData("[Desktop Entry]\nType=Application\nName=O\nExec=o\nOnlyShowIn=KDE;\n");
        QVERIFY(!only.isVisibleIn(QStringLiteral("Vitrum")));
        QVERIFY(only.isVisibleIn(QStringLiteral("Vitrum:KDE")));
        const auto not_ = DesktopEntry::fromData("[Desktop Entry]\nType=Application\nName=N\nExec=n\nNotShowIn=Vitrum;\n");
        QVERIFY(!not_.isVisibleIn(QStringLiteral("Vitrum")));
        const auto link = DesktopEntry::fromData("[Desktop Entry]\nType=Link\nName=L\nURL=https://example.org\n");
        QVERIFY(!link.isVisibleIn(QStringLiteral("Vitrum")));
        const auto ok = DesktopEntry::fromData("[Desktop Entry]\nType=Application\nName=OK\nExec=ok\n");
        QVERIFY(ok.isVisibleIn(QStringLiteral("Vitrum")));
    }
};

QTEST_GUILESS_MAIN(TestDesktopEntry)
#include "tst_desktopentry.moc"
