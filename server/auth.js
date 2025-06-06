const { print, warn, configdir, serverdir, sendEmail } = require('./localpkg.cjs');
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

async function verify(req) {
    if (!req.path.startsWith("/api")) {
        print("verify client: (path: " + req.path + ") = true");
        return true;
    }

    if (args["override-verify"] == true) {
        print("verify client: (override) = true");
        return true;
    }

    if (isLocalHost(req)) {
        print("verify client: (isLocal) = true");
        return true;
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

function checkUser(user, password) {
    return encryptPassword(password) == user.password && user.active == true;
}

function uuid() {
    return uuidpkg.uuidv4().replace(/-/g, '');
}

async function addSession(user, ip, agent) {
    var id = uuid.v4();
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
    if (getSession(id) == null) return false;
    const data = getAuthData();
    data.sessions.find(item => item.id == id).active = true;
    return true;
}

function changeUserPassword(id, password) {
    if (getUserById(id) == null) return false;
    const data = getAuthData();
    data.users.find(item => item.id == id).password = encryptPassword(password);
    return true;
}

async function addUser(email, password) {
    var id = uuid.v4();

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
    };
}

function getAuthData() {
    return JSON.parse(fs.readFileSync(file));
}

function saveAuthData(data) {
    fs.writeFileSync(file, JSON.stringify(data));
}

async function encryptPassword(password) {
    return await bcrypt.hash(password, salts);
}

function validateString(input) {
    return typeof input === 'string' && input !== null && input !== '';
}

async function routes() {
    print("generating auth routes...");
    const express = require('express');
    const router = express.Router();

    router.post("/login", async (req, res) => {
        if (!validateString(req.body.email) || !validateString(req.body.password)) return res.status(400).json({"error": "invalid input"});
        const user = getUserByEmail(req.body.email);
        if (user == null) return res.status(403).json({"error": "invalid username"});
        if (!checkUser(user, req.body.password)) return res.status({"error": "invalid password"});
        const session = await addSession(user, req.ip, req.headers['user-agent']);
        sendEmail(req.body.email, "Verify Your Login", "<p>Someone is trying to log in to your account, and we want to verify if it's you or not.</p><br><ul><li>Location: " + (session.location.city ?? "Unknown") + ", " + (session.location.region ?? "Unknown") + ", " + (session.location.country ?? "Unknown") + "</li><li>Device: " + session.device.agent + "</li></ul><br><p><a href=\"\">Click here to approve or deny the request.</a></p>");
        return res.status(200).json({"success": "email sent"});
    });

    router.post("/approve", async (req, res) => {});

    router.post("/verifyPage", (req, res) => {
        res.sendFile(serverdir + "/sessionverify.html");
    });

    print("generated auth routes");
    return router;
}

module.exports = {
    verify,
    routes,
    verifySocket,
};