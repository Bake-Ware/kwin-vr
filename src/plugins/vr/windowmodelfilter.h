/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QObject>
#include <QQmlEngine>
#include <QSortFilterProxyModel>

namespace KWin
{
class Window;

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
    void handleWindowChanged();

    QList<Window *> m_windows;
};

class PrimaryWindowModelFilter : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(KWin::KwinWindowModel *windowModel READ windowModel WRITE setWindowModel NOTIFY windowModelChanged FINAL)
    QML_ELEMENT
public:
    explicit PrimaryWindowModelFilter(QObject *parent = nullptr);

    KwinWindowModel *windowModel() const;
    void setWindowModel(KwinWindowModel *newWindowModel);

Q_SIGNALS:
    void windowModelChanged();

protected:
    bool filterAcceptsRow(int source_row, const QModelIndex &source_parent) const override;

private:
    KwinWindowModel *m_windowModel = nullptr;
};

class OsdWindowFilter : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(KWin::KwinWindowModel *windowModel READ windowModel WRITE setWindowModel NOTIFY windowModelChanged FINAL)
    QML_ELEMENT
public:
    explicit OsdWindowFilter(QObject *parent = nullptr);

    KwinWindowModel *windowModel() const;
    void setWindowModel(KwinWindowModel *newWindowModel);

Q_SIGNALS:
    void windowModelChanged();

protected:
    bool filterAcceptsRow(int source_row, const QModelIndex &source_parent) const override;

private:
    KwinWindowModel *m_windowModel = nullptr;
};

class AbstractTransientWindowModelFilter : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(KWin::Window *forTransient READ forTransient WRITE setForTransient NOTIFY forTransientChanged FINAL)
    Q_PROPERTY(KWin::KwinWindowModel *windowModel READ windowModel WRITE setWindowModel NOTIFY windowModelChanged FINAL)
public:
    explicit AbstractTransientWindowModelFilter(QObject *parent = nullptr);

    Window *forTransient() const;
    void setForTransient(Window *newForTransient);

    KwinWindowModel *windowModel() const;
    void setWindowModel(KwinWindowModel *newWindowModel);

Q_SIGNALS:
    void forTransientChanged();
    void windowModelChanged();

protected:
    Window *filterAcceptsRowCommon(int source_row, const QModelIndex &source_parent) const;

private:
    void handleForTransientDestroyed();

    Window *m_forTransient = nullptr;
    KwinWindowModel *m_windowModel = nullptr;
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

class HudWindowFilter : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(KWin::KwinWindowModel *windowModel READ windowModel WRITE setWindowModel NOTIFY windowModelChanged FINAL)
    Q_PROPERTY(bool showNotifications READ showNotifications WRITE setShowNotifications NOTIFY showNotificationsChanged FINAL)
    Q_PROPERTY(bool showOsd READ showOsd WRITE setShowOsd NOTIFY showOsdChanged FINAL)
    Q_PROPERTY(bool showDock READ showDock WRITE setShowDock NOTIFY showDockChanged FINAL)
    Q_PROPERTY(bool showAppletPopup READ showAppletPopup WRITE setShowAppletPopup NOTIFY showAppletPopupChanged FINAL)
    QML_ELEMENT
public:
    explicit HudWindowFilter(QObject *parent = nullptr);

    KwinWindowModel *windowModel() const;
    void setWindowModel(KwinWindowModel *newWindowModel);

    bool showNotifications() const;
    void setShowNotifications(bool show);

    bool showOsd() const;
    void setShowOsd(bool show);

    bool showDock() const;
    void setShowDock(bool show);

    bool showAppletPopup() const;
    void setShowAppletPopup(bool show);

Q_SIGNALS:
    void windowModelChanged();
    void showNotificationsChanged();
    void showOsdChanged();
    void showDockChanged();
    void showAppletPopupChanged();

protected:
    bool filterAcceptsRow(int source_row, const QModelIndex &source_parent) const override;

private:
    KwinWindowModel *m_windowModel = nullptr;
    bool m_showNotifications = true;
    bool m_showOsd = true;
    bool m_showDock = true;
    bool m_showAppletPopup = true;
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

} // namespace KWin
