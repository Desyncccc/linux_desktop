// SPDX-License-Identifier: GPL-3.0-or-later
#include "keyfilter.h"

#include <QKeyEvent>
#include <QSignalSpy>
#include <QTest>
#include <QWindow>

class TestKeyFilter : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void mapping_data()
    {
        QTest::addColumn<int>("key");
        QTest::addColumn<int>("mods");
        QTest::addColumn<QString>("name");
        QTest::newRow("win+d") << int(Qt::Key_D) << int(Qt::MetaModifier) << "showDesktop";
        QTest::newRow("win+e") << int(Qt::Key_E) << int(Qt::MetaModifier) << "explorer";
        QTest::newRow("win+r") << int(Qt::Key_R) << int(Qt::MetaModifier) << "run";
        QTest::newRow("win+l") << int(Qt::Key_L) << int(Qt::MetaModifier) << "lock";
        QTest::newRow("win+left") << int(Qt::Key_Left) << int(Qt::MetaModifier) << "snapLeft";
        QTest::newRow("win+3") << int(Qt::Key_3) << int(Qt::MetaModifier) << "taskbar:2";
        QTest::newRow("alt+tab") << int(Qt::Key_Tab) << int(Qt::AltModifier) << "switchNext";
        QTest::newRow("alt+shift+tab") << int(Qt::Key_Backtab) << int(Qt::AltModifier | Qt::ShiftModifier) << "switchPrev";
        QTest::newRow("alt+f4") << int(Qt::Key_F4) << int(Qt::AltModifier) << "close";
        QTest::newRow("ctrl+shift+esc") << int(Qt::Key_Escape) << int(Qt::ControlModifier | Qt::ShiftModifier) << "taskManager";
        QTest::newRow("ctrl+alt+del") << int(Qt::Key_Delete) << int(Qt::ControlModifier | Qt::AltModifier) << "secureAttention";
        QTest::newRow("print") << int(Qt::Key_Print) << 0 << "screenshot";
        QTest::newRow("plain-d") << int(Qt::Key_D) << 0 << "";
        QTest::newRow("ctrl+d") << int(Qt::Key_D) << int(Qt::ControlModifier) << "";
    }

    void mapping()
    {
        QFETCH(int, key);
        QFETCH(int, mods);
        QFETCH(QString, name);
        QCOMPARE(KeyFilter::shortcutFor(key, Qt::KeyboardModifiers(mods)), name);
    }

    void metaTapOpensStart()
    {
        KeyFilter *f = KeyFilter::instance();
        QWindow w;
        QSignalSpy spy(f, &KeyFilter::shortcut);
        QKeyEvent press(QEvent::KeyPress, Qt::Key_Super_L, Qt::MetaModifier);
        QKeyEvent release(QEvent::KeyRelease, Qt::Key_Super_L, Qt::NoModifier);
        f->eventFilter(&w, &press);
        QVERIFY(f->eventFilter(&w, &release));
        QCOMPARE(spy.count(), 1);
        QCOMPARE(spy.at(0).at(0).toString(), QStringLiteral("start"));
    }

    void metaComboDoesNotOpenStart()
    {
        KeyFilter *f = KeyFilter::instance();
        QWindow w;
        QSignalSpy spy(f, &KeyFilter::shortcut);
        QKeyEvent press(QEvent::KeyPress, Qt::Key_Super_L, Qt::MetaModifier);
        QKeyEvent d(QEvent::KeyPress, Qt::Key_D, Qt::MetaModifier);
        QKeyEvent release(QEvent::KeyRelease, Qt::Key_Super_L, Qt::NoModifier);
        f->eventFilter(&w, &press);
        QVERIFY(f->eventFilter(&w, &d));
        QVERIFY(!f->eventFilter(&w, &release));
        QCOMPARE(spy.count(), 1);
        QCOMPARE(spy.at(0).at(0).toString(), QStringLiteral("showDesktop"));
    }

    void altTabCommitsOnRelease()
    {
        KeyFilter *f = KeyFilter::instance();
        QWindow w;
        QSignalSpy spy(f, &KeyFilter::shortcut);
        QKeyEvent tab(QEvent::KeyPress, Qt::Key_Tab, Qt::AltModifier);
        QKeyEvent altUp(QEvent::KeyRelease, Qt::Key_Alt, Qt::NoModifier);
        f->eventFilter(&w, &tab);
        QVERIFY(f->switching());
        f->eventFilter(&w, &altUp);
        QVERIFY(!f->switching());
        QCOMPARE(spy.count(), 2);
        QCOMPARE(spy.at(1).at(0).toString(), QStringLiteral("switchCommit"));
    }

    void lockedSwallowsNothing()
    {
        KeyFilter *f = KeyFilter::instance();
        f->setLocked(true);
        QWindow w;
        QSignalSpy spy(f, &KeyFilter::shortcut);
        QKeyEvent d(QEvent::KeyPress, Qt::Key_D, Qt::MetaModifier);
        QVERIFY(!f->eventFilter(&w, &d));
        QCOMPARE(spy.count(), 0);
        f->setLocked(false);
    }

    void ignoresNonWindowTargets()
    {
        KeyFilter *f = KeyFilter::instance();
        QObject notAWindow;
        QSignalSpy spy(f, &KeyFilter::shortcut);
        QKeyEvent d(QEvent::KeyPress, Qt::Key_D, Qt::MetaModifier);
        QVERIFY(!f->eventFilter(&notAWindow, &d));
        QCOMPARE(spy.count(), 0);
    }
};

QTEST_MAIN(TestKeyFilter)
#include "tst_keyfilter.moc"
