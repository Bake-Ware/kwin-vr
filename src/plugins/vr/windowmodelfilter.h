/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef WINDOWMODELFILTER_H
#define WINDOWMODELFILTER_H

#include <QObject>
#include <QQmlEngine>

#include <QAbstractListModel>
#include <QPointer>
#include <QSortFilterProxyModel>

#include "kwincompat.h"

namespace KWin
{
class Window;
// class LogicalOutput;
class KwinWindowModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
public:
    enum Roles {
        WindowRole = Qt::UserRole + 1,
    };

    explicit KwinWindowModel(QObject *parent = nullptr);

    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;

private:
    void markRoleChanged(Window *window, int role);
    void handleWindowAdded(Window *window);
    void handleWindowRemoved(Window *window);

    QList<Window *> m_windows;
};

class PrimaryWindowModelFilter : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(KWin::KwinWindowModel *windowModel READ windowModel WRITE setWindowModel NOTIFY windowModelChanged FINAL)
    Q_PROPERTY(KWin::LogicalOutput *output READ output WRITE setOutput NOTIFY outputChanged FINAL)
    QML_ELEMENT
public:
    explicit PrimaryWindowModelFilter(QObject *parent = nullptr);

    KWin::KwinWindowModel *windowModel() const;
    void setWindowModel(KWin::KwinWindowModel *newWindowModel);

    KWin::LogicalOutput *output() const;
    void setOutput(KWin::LogicalOutput *newOutput);

Q_SIGNALS:
    void windowModelChanged();

    void outputChanged();

protected:
    bool filterAcceptsRow(int source_row, const QModelIndex &source_parent) const override;

private:
    KWin::KwinWindowModel *m_windowModel = nullptr;
    KWin::LogicalOutput *m_output = nullptr;
};

class TransientWindowModelFilter : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(KWin::Window *forTransient READ forTransient WRITE setForTransient NOTIFY forTransientChanged)
    Q_PROPERTY(KWin::KwinWindowModel *windowModel READ windowModel WRITE setWindowModel NOTIFY windowModelChanged FINAL)
    QML_ELEMENT
public:
    explicit TransientWindowModelFilter(QObject *parent = nullptr);

    KWin::Window *forTransient() const;
    void setForTransient(KWin::Window *newForTransient);

    KWin::KwinWindowModel *windowModel() const;
    void setWindowModel(KWin::KwinWindowModel *newWindowModel);
Q_SIGNALS:
    void forTransientChanged();
    void windowModelChanged();

protected:
    bool filterAcceptsRow(int source_row, const QModelIndex &source_parent) const override;

private:
    KWin::Window *m_forTransient = nullptr;
    KWin::KwinWindowModel *m_windowModel = nullptr;
};

class OsdWindowFilter : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(KWin::KwinWindowModel *windowModel READ windowModel WRITE setWindowModel NOTIFY windowModelChanged FINAL)
    QML_ELEMENT
public:
    explicit OsdWindowFilter(QObject *parent = nullptr);

    KWin::KwinWindowModel *windowModel() const;
    void setWindowModel(KWin::KwinWindowModel *newWindowModel);

Q_SIGNALS:
    void windowModelChanged();

protected:
    bool filterAcceptsRow(int source_row, const QModelIndex &source_parent) const override;

private:
    KWin::KwinWindowModel *m_windowModel = nullptr;
};

class AbstractTransientWindowModelFilter : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(KWin::Window *forTransient READ forTransient WRITE setForTransient NOTIFY forTransientChanged)
    Q_PROPERTY(KWin::KwinWindowModel *windowModel READ windowModel WRITE setWindowModel NOTIFY windowModelChanged FINAL)
public:
    explicit AbstractTransientWindowModelFilter(QObject *parent = nullptr);

    KWin::Window *forTransient() const;
    void setForTransient(KWin::Window *newForTransient);

    KWin::KwinWindowModel *windowModel() const;
    void setWindowModel(KWin::KwinWindowModel *newWindowModel);
Q_SIGNALS:
    void forTransientChanged();
    void windowModelChanged();

protected:
    KWin::Window *filterAcceptsRowCommon(int source_row, const QModelIndex &source_parent) const;
    // bool filterAcceptsRow(int source_row, const QModelIndex &source_parent) const override;
private:
    KWin::Window *m_forTransient = nullptr;
    KWin::KwinWindowModel *m_windowModel = nullptr;
};

class TransientNormalWindowFilter : public AbstractTransientWindowModelFilter
{
    Q_OBJECT
    QML_ELEMENT
public:
    explicit TransientNormalWindowFilter(QObject *parent = nullptr);

protected:
    bool filterAcceptsRow(int source_row, const QModelIndex &source_parent) const override;
};

class TransientMenusWindowFilter : public AbstractTransientWindowModelFilter
{
    Q_OBJECT
    QML_ELEMENT
public:
    explicit TransientMenusWindowFilter(QObject *parent = nullptr);

protected:
    bool filterAcceptsRow(int source_row, const QModelIndex &source_parent) const override;
};

}
#endif // WINDOWMODELFILTER_H
