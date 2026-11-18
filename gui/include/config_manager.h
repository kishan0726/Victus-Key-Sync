#pragma once
#include <QFileSystemWatcher>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

// Reads and writes the two files the engine watches:
//   ~/.config/victus-sync/config.json  (settings)
//   ~/.config/victus-sync/state.json   (power on/off, also changed by Super+F4)
class ConfigManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool power READ power WRITE setPower NOTIFY powerChanged)
    Q_PROPERTY(QString music READ music WRITE setMusic NOTIFY musicChanged)
    Q_PROPERTY(QString base READ base WRITE setBase NOTIFY baseChanged)
    Q_PROPERTY(QString colour READ colour WRITE setColour NOTIFY colourChanged)
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY modeChanged)
    Q_PROPERTY(int brightness READ brightness WRITE setBrightness NOTIFY brightnessChanged)
    Q_PROPERTY(double sensitivity READ sensitivity WRITE setSensitivity NOTIFY sensitivityChanged)
    Q_PROPERTY(double hold READ hold WRITE setHold NOTIFY effectChanged)
    Q_PROPERTY(double fade READ fade WRITE setFade NOTIFY effectChanged)
    Q_PROPERTY(QStringList effectColours READ effectColours NOTIFY effectChanged)

public:
    explicit ConfigManager(QObject *parent = nullptr);

    bool power() const;
    QString music() const;
    QString base() const;
    QString colour() const;
    QString mode() const;
    int brightness() const;
    double sensitivity() const;
    double hold() const;
    double fade() const;
    QStringList effectColours() const;

    void setPower(bool on);
    void setMusic(const QString &v);
    void setBase(const QString &v);
    void setColour(const QString &hex);
    void setMode(const QString &v);
    void setBrightness(int v);
    void setSensitivity(double v);
    void setHold(double v);
    void setFade(double v);

    Q_INVOKABLE double bandLow(const QString &name) const;
    Q_INVOKABLE double bandHigh(const QString &name) const;
    Q_INVOKABLE void setBand(const QString &name, double low, double high);
    Q_INVOKABLE void setEffectColour(int index, const QString &hex);
    Q_INVOKABLE void addEffectColour();
    Q_INVOKABLE void removeEffectColour(int index);

signals:
    void powerChanged();
    void musicChanged();
    void baseChanged();
    void colourChanged();
    void modeChanged();
    void brightnessChanged();
    void sensitivityChanged();
    void effectChanged();

private:
    void load();
    void loadPower();
    void reloadPower();
    void scheduleSave();
    void saveConfig();
    QJsonObject effect() const;

    QString m_dir;
    QString m_configPath;
    QString m_statePath;
    QJsonObject m_root;
    QJsonObject m_state;
    bool m_power = true;
    QTimer m_saveTimer;
    QFileSystemWatcher m_watcher;
};
