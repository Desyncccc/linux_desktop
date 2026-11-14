// SPDX-License-Identifier: GPL-3.0-or-later
#include "authenticator.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QPointer>
#include <thread>

#ifdef VITRUM_HAVE_PAM
#include <cstdlib>
#include <cstring>
#include <pwd.h>
#include <security/pam_appl.h>
#include <unistd.h>

namespace {
int conversation(int num, const pam_message **msg, pam_response **resp, void *data)
{
    auto *reply = static_cast<pam_response *>(calloc(size_t(num), sizeof(pam_response)));
    if (!reply)
        return PAM_BUF_ERR;
    for (int i = 0; i < num; ++i) {
        if (msg[i]->msg_style == PAM_PROMPT_ECHO_OFF || msg[i]->msg_style == PAM_PROMPT_ECHO_ON)
            reply[i].resp = strdup(static_cast<const char *>(data));
    }
    *resp = reply;
    return PAM_SUCCESS;
}

bool pamCheck(const QByteArray &password, QString *error)
{
    const passwd *pw = getpwuid(getuid());
    if (!pw) {
        *error = QStringLiteral("Unknown user");
        return false;
    }
    const char *service = QFileInfo::exists(QStringLiteral("/etc/pam.d/vitrum")) ? "vitrum" : "login";
    const pam_conv conv = {conversation, const_cast<char *>(password.constData())};
    pam_handle_t *handle = nullptr;
    int rc = pam_start(service, pw->pw_name, &conv, &handle);
    if (rc == PAM_SUCCESS)
        rc = pam_authenticate(handle, 0);
    if (rc == PAM_SUCCESS)
        rc = pam_acct_mgmt(handle, 0);
    if (rc != PAM_SUCCESS)
        *error = QString::fromLocal8Bit(pam_strerror(handle, rc));
    if (handle) {
        if (rc == PAM_SUCCESS)
            pam_setcred(handle, PAM_REFRESH_CRED);
        pam_end(handle, rc);
    }
    return rc == PAM_SUCCESS;
}
} // namespace
#endif

Authenticator::Authenticator(QObject *parent)
    : QObject(parent)
{
}

Authenticator *Authenticator::create(QQmlEngine *engine, QJSEngine *)
{
    return new Authenticator(engine);
}

bool Authenticator::available() const
{
#ifdef VITRUM_HAVE_PAM
    return true;
#else
    return false;
#endif
}

void Authenticator::authenticate(const QString &password)
{
    if (m_busy)
        return;
    m_busy = true;
    Q_EMIT busyChanged();
    QPointer<Authenticator> self(this);
    const QByteArray pwd = password.toUtf8();
    std::thread([self, pwd]() {
        QString error;
        bool ok = false;
#ifdef VITRUM_HAVE_PAM
        ok = pamCheck(pwd, &error);
#else
        Q_UNUSED(pwd)
        error = QStringLiteral("This build has no PAM support");
#endif
        if (!ok && error.isEmpty())
            error = QStringLiteral("The password is incorrect. Try again.");
        else if (!ok)
            error = QStringLiteral("The password is incorrect. Try again.");
        if (!ok)
            std::this_thread::sleep_for(std::chrono::milliseconds(800)); // slow down guessing
        QMetaObject::invokeMethod(qApp, [self, ok, error] {
            if (!self)
                return;
            self->m_busy = false;
            Q_EMIT self->busyChanged();
            if (ok)
                Q_EMIT self->succeeded();
            else
                Q_EMIT self->failed(error);
        });
    }).detach();
}
