const { print, warn, configdir, serverdir, sendEmail, debug } = require('./localpkg.cjs');
const { readFile, writeFile } = require('fs/promises');
const fs = require('fs');
const bcrypt = require('bcrypt');
const uuidpkg = require('uuid');
const axios = require('axios');

const salts = 10;
const file = serverdir + "/accounts.json";
const args = require('minimist')(process.argv.slice(2));

(() => {
    const data = getAuthData();
    data.sessions ??= [];
    data.users ??= [];
    saveAuthData(data);
})();

if (!fs.existsSync(file)) {
    print("creating " + file);
    fs.writeFileSync(file, JSON.stringify({"sessions": [], "users": []}), { flag: 'wx' });
}

async function filterSessions() {
    const data = await getAuthDataAsync();
    data.sessions = data.sessions.filter(session => {
        const status = new Date(session.created).getTime() >= Date.now() - 10 * 60 * 1000 && session.active == false;
        if (status == false) print("removing session " + session.id);
        return status;
    });
    await saveAuthDataAsync(data);
}

async function verify(req) {
    if (!req.path.startsWith("/api")) {
        print("verify client: (path: " + req.path + ") = true");
        return {"status": true, "reason": null};
    }

    if (args["override-verify"] == true) {
        print("verify client: (override) = true");
        return {"status": true, "reason": null};
    }

    if (isLocalHost(req)) {
        print("verify client: (isLocal) = true");
        return {"status": true, "reason": null};
    }

    const sessionCode = req.headers["authentication"];
    const password = req.headers["password"];
    const status = getSession(req.body.id) != null && password == process.env.PASSWORD;
    const log = "verify client: (session code: " + sessionCode + ") (password match: " + (password == process.env.PASSWORD) + ") = " + status;

    if (status) {
        print(log);
        return {"status": true, "reason": null};
    } else {
        warn(log);
        return {"status": false, "reason": "invalid session"};
    }
}

async function verifySocket(handshake) {
    const sessionCode = handshake.headers["authentication"];
    const password = handshake.headers["password"];
    const status = getSession(req.body.id) != null && password == process.env.PASSWORD;
    const log = "verify client: (session code: " + sessionCode + ") (password match: " + (password == process.env.PASSWORD) + ") = " + status;

    if (status) {
        print(log);
        return {"status": true, "reason": null};
    } else {
        warn(log);
        return {"status": false, "reason": "invalid session"};
    }
}

function getSession(id) {
    return getAuthData().sessions.find(item => item.id == id && item.active == true);
}

function getUserByEmail(email) {
    return getAuthData().users.find(item => item.email == email);
}

function getUserById(id) {
    return getAuthData().users.find(item => item.id == id);
}

async function compareHashes(password, hash) {
    return await bcrypt.compare(password, hash);
}

async function checkUser(user, password) {
    const compare = await compareHashes(password, user.password);
    const status = compare && user.active == true;
    print("checkUser: (match: " + compare + ") (active: " + user.active + ") = " + status);
    return status;
}

function uuid() {
    return uuidpkg.v4().replace(/-/g, '');
}

async function addSession(user, ip, agent) {
    var id = uuid();
    var city;
    var region;
    var country;

    while (true) {
        if (getSession(id) != null) {
            id = uuid();
        } else {
            break;
        }
    }

    try {
        const response = await axios.get(`https://ipapi.co/${ip}/json/`);
        city = response["city"];
        region = response["region_code"];
        country = response["country_code"];
    } catch (error) {
        warn('ip.location: ' + error);
    }

    const session = {
        "id": id,
        "user": user.id,
        "active": false,
        "created": new Date().toISOString(),
        "verificationCode": uuid(),
        "location": {
            "city": city,
            "region": region,
            "country": country,
        },
        "device": {
            "agent": agent,
        },
    };
    
    const data = getAuthData();
    data.sessions.push(session);
    saveAuthData(data);
    return session;
}

function verifySession(id) {
    const data = getAuthData();
    data.sessions.find(item => item.id == id).active = true;
    saveAuthData(data);
    return true;
}

function changeUserPassword(id, password) {
    if (getUserById(id) == null) return false;
    const data = getAuthData();
    data.users.find(item => item.id == id).password = encryptPassword(password);
    return true;
}

async function addUser(email, password) {
    var id = uuid();

    while (true) {
        if (getUserById(id) != null) {
            id = uuid();
        } else {
            break;
        }
    }

    const user = {
        "id": id,
        "email": email,
        "password": encryptPassword(password),
        "active": true,
    };
}

function getAuthData() {
    return JSON.parse(fs.readFileSync(file));
}

async function getAuthDataAsync() {
    return JSON.parse(await readFile(file));
}

function saveAuthData(data) {
    fs.writeFileSync(file, JSON.stringify(data, null, 4));
}

async function saveAuthDataAsync(data) {
    return await writeFile(file, JSON.stringify(data, null, 4));
}

async function encryptPassword(password) {
    return await bcrypt.hash(password, salts);
}

function validateString(input) {
    return typeof input === 'string' && input !== null && input !== '';
}

function routes() {
    print("generating auth routes...");
    const express = require('express');
    const router = express.Router();

    router.post("/login", async (req, res) => {
        if (!validateString(req.body.email) || !validateString(req.body.password)) return res.status(400).json({"error": "invalid input"});
        const user = getUserByEmail(req.body.email);
        if (user == null) return res.status(403).json({"error": "invalid username"});
        if (!(await checkUser(user, req.body.password))) return res.status(403).json({"error": "invalid password"});
        print("ip: " + req.ip);
        const session = await addSession(user, req.ip, req.headers['user-agent']);
        const location = (session.location.city ?? "Unknown") + ", " + (session.location.region ?? "Unknown") + ", " + (session.location.country ?? "Unknown");
        const url = (debug ? "http://localhost" : "https://home.calebh101.com") + "/auth/verifyPage?id=" + session.verificationCode + "&location=" + encodeURIComponent(location) + "&agent=" + encodeURIComponent(session.device.agent) + "&debug=" + (debug ? 1 : 0);
        print("sending url: " + url);
        sendEmail(req.body.email, "Verify Your Login", "<p>Someone is trying to log in to your account, and we want to verify if it's you or not.</p><br><ul><li>Location: " + location + "</li><li>Device: " + session.device.agent + "</li></ul><br><p><a href=\"" + url + "\">Click here to approve the request.</a></p>");
        return res.status(200).json({"success": "email sent"});
    });

    router.post("/approve", async (req, res) => {
        const code = req.query.id;
        print("received approve code: " + code);
        const session = getAuthData().sessions.find(item => item.verificationCode == code && item.active == false);
        if (session == null) return res.status(403).json({"error": "invalid code"});
        if (new Date(session.created).getTime() < Date.now() - 10 * 60 * 1000) res.status(403).json({"error": "expired code"});
        verifySession(session.id);
        return res.status(200).json({"success": "true"});
    });

    router.get("/verifyPage", (req, res) => {
        res.sendFile(serverdir + "/sessionverify.html");
    });

    print("generated auth routes");
    return router;
}

module.exports = {
    verify,
    routes,
    verifySocket,
    filterSessions,
};