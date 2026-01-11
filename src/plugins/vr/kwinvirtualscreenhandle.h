/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef KWINVIRTUALSCREENHANDLE_H
#define KWINVIRTUALSCREENHANDLE_H

#include <QObject>
#include <QQmlEngine>
#include <qsize.h>

#include "kwincompat.h"

namespace KWin
{
// class BackendOutput;
class KwinVirtualScreenParams
{
    Q_GADGET
    Q_PROPERTY(QSize size READ size WRITE setSize FINAL)
    Q_PROPERTY(QString name READ name WRITE setName FINAL)
    Q_PROPERTY(QString description READ description WRITE setDescription FINAL)
    Q_PROPERTY(qreal scale READ scale WRITE setScale FINAL)
    QML_VALUE_TYPE(kwinVirtualScreenParams)
public:
    QSize size() const;
    void setSize(const QSize &newSize);
    QString name() const;
    void setName(const QString &newName);

    QString description() const;
    void setDescription(const QString &newDescription);

    qreal scale() const;
    void setScale(qreal newScale);

    // private:
    QString m_name;
    QString m_description;
    QSize m_size;
    qreal m_scale;
};

/* Create a virtual output (virtual screen) in KWin */
class KwinVirtualScreenHandle : public QObject
{
    Q_OBJECT
    Q_PROPERTY(KWin::BackendOutput *output READ output NOTIFY outputChanged FINAL)
    Q_PROPERTY(KWin::KwinVirtualScreenParams params READ params WRITE setParams NOTIFY paramsChanged FINAL)
    QML_ELEMENT
public:
    explicit KwinVirtualScreenHandle(QObject *parent = nullptr);
    ~KwinVirtualScreenHandle();
    KWin::BackendOutput *output() const;

    KWin::KwinVirtualScreenParams params() const;
    void setParams(const KWin::KwinVirtualScreenParams &newParams);

Q_SIGNALS:
    void outputChanged();
    void paramsChanged();

private:
    void setOutput(KWin::BackendOutput *newOutput);

    KWin::BackendOutput *m_output = nullptr;
    KWin::KwinVirtualScreenParams m_params;
};
}

#endif // KWINVIRTUALSCREENHANDLE_H
