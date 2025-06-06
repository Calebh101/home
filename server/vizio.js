const { print, warn } = require('./localpkg.cjs');
const wol = require('wol');
const fs = require('fs');
const Path = require('path');
const https = require('https');

print("vizio: initializing");
const tvdata = JSON.parse(fs.readFileSync(Path.join(__dirname, 'tv-data.json')));
const tvapps = JSON.parse(fs.readFileSync(Path.join(__dirname, 'tv-apps.json')));

function tvs() {
    return JSON.parse(fs.readFileSync(Path.join(__dirname, 'tvs.json'))).tvs;
}

function getTv(id) {
    tv = tvs().find(item => item.id === id && item.type === "vizio");
    return tv;
}

async function wake(id) {
    const tv = getTv(id);
    if (tv == null) return null;
    const mac = tv.mac;
    print("wol: " + mac);

    const status = await new Promise((resolve) => {
        wol.wake(mac, function(error) {
            if (error) {
                warn("wol: fail: " + error);
                resolve(false);
            } else {
                print("wol: success");
                resolve(true);
            }
        });
    });

    const result = await request(id, "/key_command/", "PUT", {
        "KEYLIST": [{
            "CODESET": 11,
            "CODE": 1,
            "ACTION": "KEYPRESS",
        }],
    });

    return {
        "status": status,
    };
}

async function request(id, endpoint, method = "GET", body, timeout = null) {
    const tv = getTv(id);
    if (tv == null) return null;
    const address = `${tv.ip}:${tv.port}`;
    print("vizio: request: " + endpoint + " to tv " + address + " with auth " + tv.code);

    const options = {
        hostname: tv.ip,
        port: tv.port,
        path: endpoint,
        method: method,
        rejectUnauthorized: false,
        headers: {
            "Auth": tv.code,
            "Content-Type": "application/json",
        },
    };

    return new Promise((resolve, reject) => {
        const req = https.request(options, (res) => {
            print("vizio: request: status code " + res.statusCode);
            let data = '';

            res.on('data', (chunk) => {
                data += chunk;
            });

            res.on('end', () => {
                try {
                    print("response: " + data);
                    const response = JSON.parse(data);
                    resolve(response);
                } catch (e) {
                    warn("vizio: request: " + e);
                    resolve(null);
                }
            });
        });

        if (timeout) {
            req.setTimeout(timeout, () => {
                warn("vizio: request: timeout (" + timeout + ")");
                req.destroy();
                resolve(null);
            });
        }

        req.on('error', (e) => {
            print("vizio: request.promise: " + e);
            resolve(null);
        });

        if (body) {
            req.write(JSON.stringify(body));
        }

        print("vizio: request: end");
        req.end();
    });
}

async function editSetting(id, name, value) {
    const setting = tvdata.settings.find(item => item.name == name);
    if (setting == null) return null;
    return await request(id, "/menu_native/dynamic/tv_settings/" + setting.category + "/" + name, "PUT", {
        "REQUEST": "MODIFY",
        "HASHVAL": setting.hash[id],
        "VALUE": value
    });
}

async function launchApp(id, name) {
    const app = tvapps.apps.find(item => item.name == name);
    if (app == null) return null;
    const config = app.config[0];
    return await request(id, "/app/launch", "PUT", {
        "VALUE": {
            "MESSAGE": config.MESSAGE,
            "NAME_SPACE": config.NAME_SPACE,
            "APP_ID": config.APP_ID
        },
    });
}

async function getDevices(id) {
    return await request(id, "/menu_native/dynamic/tv_settings/devices", "GET");
}

module.exports = {
    getTv,
    launchApp,
    getDevices,
    wake,
    request,
    editSetting,
};