#include "config_manager.h"

#include <QColor>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>
#include <algorithm>
#include <cmath>

namespace {

QJsonArray rgb(const QColor &c) { return QJsonArray{c.red(), c.green(), c.blue()}; }

QColor colourFrom(const QJsonValue &v, const QColor &fallback)
{
    const QJsonArray a = v.toArray();
    if (a.size() != 3)
        return fallback;
    return QColor(a[0].toInt(), a[1].toInt(), a[2].toInt());
}

QJsonObject defaultConfig()
{
    return QJsonObject{
        {"bands", QJsonObject{
            {"bass",   QJsonArray{20, 150}},
            {"mid",    QJsonArray{150, 2000}},
            {"treble", QJsonArray{2000, 12000}},
        }},
        {"mode", "bands"},
        {"brightness", 200},
        {"sensitivity", 1.7},
        {"every", 2},
        {"attack", 0.6},
        {"decay", 0.12},
        {"music", "auto"},
        {"base", "colour"},
        {"colour", QJsonArray{255, 255, 255}},
        {"effect", QJsonObject{
            {"colours", QJsonArray{QJsonArray{255, 0, 0}, QJsonArray{0, 0, 255}, QJsonArray{0, 255, 0}}},
            {"hold", 2.0},
            {"fade", 3.0},
        }},
    };
}

QJsonObject readObject(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    return doc.isObject() ? doc.object() : QJsonObject{};
}

// Writes a temp file and renames it, so the engine never sees half a file.
bool writeObject(const QString &path, const QJsonObject &obj)
{
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly)) {
        qWarning() << "Cannot write" << path;
        return false;
    }
    f.write(QJsonDocument(obj).toJson());
    return f.commit();
}

} // namespace

ConfigManager::ConfigManager(QObject *parent)
    : QObject(parent)
    , m_dir(QDir::homePath() + "/.config/victus-sync")
    , m_configPath(m_dir + "/config.json")
    , m_statePath(m_dir + "/state.json")
{
    QDir().mkpath(m_dir);

    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(150);   // wait for a slider to settle before writing
    connect(&m_saveTimer, &QTimer::timeout, this, &ConfigManager::saveConfig);

    load();
    loadPower();

    // Watch the folder (not the file): saves replace the file, which breaks file watches.
    m_watcher.addPath(m_dir);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &ConfigManager::reloadPower);
}

void ConfigManager::load()
{
    m_root = defaultConfig();
    const QJsonObject saved = readObject(m_configPath);
    for (auto it = saved.begin(); it != saved.end(); ++it) {
        if ((it.key() == "bands" || it.key() == "effect") && it.value().isObject()) {
            QJsonObject merged = m_root.value(it.key()).toObject();
            const QJsonObject sub = it.value().toObject();
            for (auto s = sub.begin(); s != sub.end(); ++s)
                merged[s.key()] = s.value();
            m_root[it.key()] = merged;
        } else {
            m_root[it.key()] = it.value();   // keeps keys the GUI doesn't edit, like "every"
        }
    }
}

void ConfigManager::loadPower()
{
    m_state = readObject(m_statePath);
    m_power = m_state.value("power").toBool(true);
}

void ConfigManager::reloadPower()
{
    const bool old = m_power;
    loadPower();
    if (m_power != old)
        emit powerChanged();
}

void ConfigManager::scheduleSave() { m_saveTimer.start(); }
void ConfigManager::saveConfig() { writeObject(m_configPath, m_root); }

QJsonObject ConfigManager::effect() const { return m_root.value("effect").toObject(); }

// ---- getters ----
bool ConfigManager::power() const { return m_power; }
QString ConfigManager::music() const { return m_root.value("music").toString("auto"); }
QString ConfigManager::base() const { return m_root.value("base").toString("colour"); }
QString ConfigManager::mode() const { return m_root.value("mode").toString("bands"); }
int ConfigManager::brightness() const { return m_root.value("brightness").toInt(200); }
double ConfigManager::sensitivity() const { return m_root.value("sensitivity").toDouble(1.7); }
double ConfigManager::hold() const { return effect().value("hold").toDouble(2.0); }
double ConfigManager::fade() const { return effect().value("fade").toDouble(3.0); }

QString ConfigManager::colour() const
{
    return colourFrom(m_root.value("colour"), Qt::white).name();   // "#rrggbb"
}

QStringList ConfigManager::effectColours() const
{
    QStringList out;
    const QJsonArray arr = effect().value("colours").toArray();
    for (const QJsonValue &v : arr)
        out << colourFrom(v, Qt::white).name();
    return out;
}

// ---- setters ----
void ConfigManager::setPower(bool on)
{
    if (on == m_power)
        return;
    m_power = on;
    m_state["power"] = on;
    writeObject(m_statePath, m_state);   // immediate: this is a switch, not a slider
    emit powerChanged();
}

void ConfigManager::setMusic(const QString &v)
{
    if (!QStringList{"auto", "on", "off"}.contains(v) || v == music())
        return;
    m_root["music"] = v;
    emit musicChanged();
    scheduleSave();
}

void ConfigManager::setBase(const QString &v)
{
    if (!QStringList{"colour", "effect"}.contains(v) || v == base())
        return;
    m_root["base"] = v;
    emit baseChanged();
    scheduleSave();
}

void ConfigManager::setColour(const QString &hex)
{
    const QColor c(hex);
    if (!c.isValid() || c.name() == colour())
        return;
    m_root["colour"] = rgb(c);
    emit colourChanged();
    scheduleSave();
}

void ConfigManager::setMode(const QString &v)
{
    if (!QStringList{"bands", "pulse", "rainbow"}.contains(v) || v == mode())
        return;
    m_root["mode"] = v;
    emit modeChanged();
    scheduleSave();
}

void ConfigManager::setBrightness(int v)
{
    v = std::clamp(v, 0, 255);
    if (v == brightness())
        return;
    m_root["brightness"] = v;
    emit brightnessChanged();
    scheduleSave();
}

void ConfigManager::setSensitivity(double v)
{
    v = std::round(std::clamp(v, 1.1, 4.0) * 100) / 100;
    if (v == sensitivity())
        return;
    m_root["sensitivity"] = v;
    emit sensitivityChanged();
    scheduleSave();
}

void ConfigManager::setHold(double v)
{
    v = std::round(std::clamp(v, 0.0, 60.0) * 10) / 10;
    if (v == hold())
        return;
    QJsonObject e = effect();
    e["hold"] = v;
    m_root["effect"] = e;
    emit effectChanged();
    scheduleSave();
}

void ConfigManager::setFade(double v)
{
    v = std::round(std::clamp(v, 0.2, 60.0) * 10) / 10;
    if (v == fade())
        return;
    QJsonObject e = effect();
    e["fade"] = v;
    m_root["effect"] = e;
    emit effectChanged();
    scheduleSave();
}

// ---- frequency bands ----
double ConfigManager::bandLow(const QString &name) const
{
    return m_root.value("bands").toObject().value(name).toArray().at(0).toDouble(20);
}

double ConfigManager::bandHigh(const QString &name) const
{
    return m_root.value("bands").toObject().value(name).toArray().at(1).toDouble(20000);
}

void ConfigManager::setBand(const QString &name, double low, double high)
{
    low = std::clamp(std::round(low), 20.0, 19999.0);
    high = std::clamp(std::round(high), low + 1, 20000.0);   // engine needs low < high
    QJsonObject bands = m_root.value("bands").toObject();
    bands[name] = QJsonArray{low, high};
    m_root["bands"] = bands;
    scheduleSave();
}

// ---- effect colour steps ----
void ConfigManager::setEffectColour(int index, const QString &hex)
{
    const QColor c(hex);
    QJsonObject e = effect();
    QJsonArray cols = e.value("colours").toArray();
    if (!c.isValid() || index < 0 || index >= cols.size())
        return;
    cols[index] = rgb(c);
    e["colours"] = cols;
    m_root["effect"] = e;
    emit effectChanged();
    scheduleSave();
}

void ConfigManager::addEffectColour()
{
    QJsonObject e = effect();
    QJsonArray cols = e.value("colours").toArray();
    if (cols.size() >= 8)
        return;
    cols.append(cols.isEmpty() ? rgb(Qt::white) : cols.last());   // copy of the last step
    e["colours"] = cols;
    m_root["effect"] = e;
    emit effectChanged();
    scheduleSave();
}

void ConfigManager::removeEffectColour(int index)
{
    QJsonObject e = effect();
    QJsonArray cols = e.value("colours").toArray();
    if (cols.size() <= 2 || index < 0 || index >= cols.size())   // the engine needs 2 or more
        return;
    cols.removeAt(index);
    e["colours"] = cols;
    m_root["effect"] = e;
    emit effectChanged();
    scheduleSave();
}
