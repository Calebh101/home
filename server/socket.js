const express = require("express");
const http = require("http");
const https = require("https");
const fs = require('fs');
const { Server } = require("socket.io");
const { print, buildAppCommand, command, getConfig, getData, stringToBool, debug, configdir, saveData, serverdir } = require("./localpkg.cjs");
const { warn } = require("console");
const path = require("path");
const EventEmitter = require('events');

class StreamController extends EventEmitter {
  send(data) {
    this.emit('data', data);
  }

  close() {
    this.emit('end');
  }
}

var port = 3000;
var secure = true;
var stateIo;
var dashboardIo;
var dashboardIds = [];
var server;
var controller = new StreamController();

async function stateCommand(cmd, service = "state.status") {
    var out;
    await command(null, cmd, service, (stdout) => {
        out = stdout;
    }, true, true);
    return out;
}

function getSocketPort() {
    return port;
}

async function getState() {
    var screenstate;
    var volstate;
    var brightnessstate;
    var appstate;
    var temps;
    var themestate;

    try {
        getData();
    } catch (e) {
        warn("getData error: " + e);
        saveData({});
    }

    try {
        await command(null, 'DISPLAY=:0 xset q | grep -q "Monitor is On" && echo 1 || echo 0', "screen.status", (stdout) => {
            screenstate = parseInt(stdout.trim(), 10);
        }, true, true);

        await command(null, buildAppCommand('state_dump'), "getState", (stdout) => {
            if (stdout == '') stdout = '{"error": "unavailable"}';
            appstate = JSON.parse(stdout.trim());
        }, true, true);

        await command(null, "amixer get Master | grep -o '[0-9]*%' | head -n1 | tr -d '%'", 'volume.status', (stdout) => {
            volstate = parseInt(stdout.trim(), 10);
        }, true, true);

        await command(null, "echo $(( 100 * $(cat /sys/class/backlight/*/brightness) / $(cat /sys/class/backlight/*/max_brightness) ))", 'brightness.status', (stdout) => {
            brightnessstate = parseInt(stdout.trim(), 10);
        }, true, true);

        await command(null, "sensors -j", "temps.status", (stdout) => {
            if (stdout == '') stdout = '{"error": "unavailable"}';
            temps = JSON.parse(stdout.trim());
        }, true, true);

        function getTime(item) {
            const time = (new Date().getTime() - new Date(item.date).getTime());
            return time;
        }

        function getExpires(item) {
            const time = item.expires * 60 * 60 * 1000;
            return time;
        }

        // filter (without writing changes)
        const announcements = (getData().announcements ?? []).filter(item => (item.expires == null) || (getTime(item) < getExpires(item))).filter(item => (new Date(item.date) <= new Date()));
        const dashboardData = Object.fromEntries(Object.entries((getData().dashboards ?? {})).filter(([_, v]) => Date.now() - new Date(v.lastUpdated) <= 3 * 60 * 60 * 1000));

        return {
            "app": appstate,
            "screen": screenstate,
            "volume": volstate,
            "brightness": brightnessstate,
            "temperature" : temps,
            "theme": themestate,
            "announcements": announcements,
            "contacts": getData().contacts,
            "fans": {
                "speed": getData().fans?.speed,
            },
            "lastRefresh": getData().lastRefreshed,
            "dashboards": dashboardData,
        };
    } catch (e) {
        warn("getState error: " + e);
        return {"error": "internal server error"};
    }
}

async function init() {
    print("setting up sockets on port " + port);
    const app = express();

    if (debug) {
        print("setting NODE_TLS_REJECT_UNAUTHORIZED to 0...");
        process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
    }

    const options = {
        cert: fs.readFileSync(path.resolve(configdir + '/cert/cert.pem')),
        key: fs.readFileSync(path.resolve(configdir + '/cert/key.pem')),
        //passphrase: fs.readFileSync(path.resolve(configdir + '/cert/pass.txt'), 'utf8').trim(),
        requestCert: false,
        rejectUnauthorized: false,
    };

    if (secure) {
        server = https.createServer(options, app);
    } else {
        server = http.createServer(app);
    }

    stateIo = new Server(server, {
        path: "/state",
        cors: {
            origin: "*",
            methods: ["GET", "POST"],
        },
        transports: ["websocket"],
    });

    stateIo.on("connection", async (socket) => {
        print("connect: " + socket.id);
        socket.emit("update", await getState());

        socket.on("disconnect", () => {
            print("disconnect: " + socket.id);
        });
    });

    setInterval(async () => {
        stateIo.emit("update", await getState());
    }, getConfig().server.statedumpinterval * 1000);

    dashboardIo = new Server(server, {
        path: "/dashboardstate",
        cors: {
            origin: "*",
            methods: ["GET", "POST"],
        },
        transports: ["websocket"],
    });

    dashboardIo.on("connection", async (socket) => {
        const id = socket.handshake.query.id;
        print("device connected: " + id);

        if (id == null || id == undefined || id == "" || dashboardIds.includes(id)) {
            print("invalid device id: " + id);
            socket.emit("update", {"error": "Your device ID needs to be a valid and unique ID.", "code": "dev-id-invalid"});
            socket.disconnect(true);
        } else {
            dashboardIds.push(id);
        }

        controller.on('data', (data) => {
            print("controller data: " + JSON.stringify(data));
            if (data.id == id) socket.emit("update", {"action": data.command});
        });

        socket.on("update", (c) => {
            // a: raw UTF-8 from data.json
            // b: parsed data from data.json
            // c: received data from socket

            if (!fs.existsSync(serverdir + '/data.json')) {
                print("creating data.json");
                fs.writeFileSync(serverdir + '/data.json', "{}", { flag: 'wx' });
            }

            fs.readFile(serverdir + '/data.json', 'utf8', (e, a) => {
                if (e) {
                    warn("data.json read error (0x0): " + e);
                    return;
                }

                try {
                    const b = JSON.parse(a);
                    b.dashboards[id] = c;

                    fs.writeFile(serverdir + '/data.json', JSON.stringify(b, null, 4), 'utf8', (e) => {
                        if (e) {
                            warn("data.json read error (0x2): " + e);
                            return;
                        }
                        print("saved data from " + id);
                    });
                } catch (e) {
                    warn("data.json parse error (0x1): " + e);
                    return;
                }
            });
        });

        socket.on('disconnect', (reason) => {
            print("client " + id + " disconnected: " + reason);
            dashboardIds = dashboardIds.filter(item => item !== id);
        });
    });

    app.get("/", (req, res) => {
        return res.status(200).json({"secure": secure});
    });

    server.listen(port, () => {
        print(`socket.io server running on http${secure ? "s" : ""}://localhost:${port}`);
    });
}

module.exports = {
    init,
    getState,
    getSocketPort,
    controller,
};