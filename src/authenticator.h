// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QObject>
#include <QQmlEngine>

// Verifies the session user's password through PAM for the lock screen.
class Authenticator : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Auth)
    QML_SINGLETON
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    static Authenticator *create(QQmlEngine *, QJSEngine *);
    bool available() const;
    bool busy() const { return m_busy; }

    Q_INVOKABLE void authenticate(const QString &password);

Q_SIGNALS:
    void busyChanged();
    void succeeded();
    void failed(const QString &message);

private:
    explicit Authenticator(QObject *parent = nullptr);
    bool m_busy = false;
};
