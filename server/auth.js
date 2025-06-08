const { print, warn, configdir, serverdir, sendEmail, debug, isLocalHost } = require('./localpkg.cjs');
const { readFile, writeFile } = require('fs/promises');
const fs = require('fs');
const bcrypt = require('bcrypt');
const uuidpkg = require('uuid');
const axios = require('axios');
const limiter = require('express-rate-limit');

const ignoreLocalHost = true;
const ignorePassword = true;
const salts = 10;
const file = serverdir + "/accounts.json";
const args = require('minimist')(process.argv.slice(2));

if (!fs.existsSync(file)) {
    print("creating " + file);
    fs.writeFileSync(file, JSON.stringify({"sessions": [], "users": []}), { flag: 'wx' });
}

if (fs.readFileSync(file) == "") {
    warn("correcting " + file);
    saveAuthData({});
}

(() => {
    const data = getAuthData();
    data.sessions ??= [];
    data.users ??= [];
    saveAuthData(data);
})();

const harshlimit = limiter({
    windowMs: 30 * 60 * 1000,
    max: 3,
    message: 'Too many requests, please try again later.',
    standardHeaders: true,
    legacyHeaders: false,
});

async function filterSessions() {
    var data;
    try {
        data = await getAuthDataAsync();
    } catch (e) {
        warn("authData: " + e);
        data = {};
    }
    data.sessions = data.sessions.filter(session => {
        var user = getUserById(session.user);
        var status = user != null && user.email == session.email && ((new Date(session.created).getTime() >= Date.now() - 30 * 60 * 1000 && session.active == false) || session.active == true);
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

    if (isLocalHost(req) && ignoreLocalHost == false) {
        print("verify client: (isLocal) = true");
        return {"status": true, "reason": null};
    }

    const sessionCode = req.headers["authentication"];
    const password = req.headers["X-Authentication-Value"];
    const status = getSession(sessionCode) != null && (password == process.env.ACCESS_CODE || ignorePassword);
    const log = "verify client: (session code: " + sessionCode + ") (password match: " + (password == process.env.ACCESS_CODE || ignorePassword) + ") = " + status;

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
    const status = getSession(sessionCode) != null && (password == process.env.ACCESS_CODE || ignorePassword);
    const log = "verify socket: (session code: " + sessionCode + ") (password match: " + (password == process.env.ACCESS_CODE || ignorePassword) + ") = " + status;

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
    print("checkUser: (match: " + compare + ") (active: " + user.active + ") = " + status + " (input: " + password + ")");
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
        "verificationCode": Math.random().toString(36).substring(2, 8),
        "location": {
            "city": city,
            "region": region,
            "country": country,
        },
        "device": {
            "agent": agent,
        },
        "email": user.email,
    };

    print("saving session " + id);
    const data = getAuthData();
    data.sessions.push(session);
    saveAuthData(data);
    return session;
}

function verifySession(id, status = true) {
    const data = getAuthData();
    data.sessions.find(item => item.id == id).active = status;
    saveAuthData(data);
    return true;
}

function changeUserPassword(id, password) {
    if (getUserById(id) == null) return false;
    const data = getAuthData();
    data.users.find(item => item.id == id).password = encryptPassword(password);
    saveAuthData(data);
    return true;
}

async function addUser(email, password, firstName, lastName) {
    if (getUserByEmail(email) != null) return null;
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
        "password": await encryptPassword(password),
        "firstName": firstName,
        "lastName": lastName,
        "active": false,
    };

    const data = getAuthData();
    data.users.push(user);
    saveAuthData(data);
    return user;
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
        if (!validateString(req.body.email) || !validateString(req.body.password)) return res.status(403).json({"error": "invalid input", "message": "Invalid email or password."});
        const user = getUserByEmail(req.body.email);
        if (user == null) return res.status(403).json({"error": "invalid username", "message": "Invalid username or password."});
        if (!(await checkUser(user, req.body.password))) return res.status(403).json({"error": "invalid password"});
        print("ip: " + req.ip);
        const minutes = 2;
        if (getAuthData().sessions.find(item => item.user == user.id && new Date(item.created).getTime() >= Date.now() - minutes * 60 * 1000 && item.active == false) != null) return res.status(403).json({"error": "too soon", "message": "Please wait at least " + minutes + " minutes before requesting another code."});
        const session = await addSession(user, req.ip, req.headers['user-agent']);
        const location = (session.location.city ?? "Unknown") + ", " + (session.location.region ?? "Unknown") + ", " + (session.location.country ?? "Unknown");
        const name = [user.firstName, user.lastName].join(" ");
        print("name: " + name);
        sendEmail(req.body.email, "Verify Your Login for " + name, "<h2>Verify Your Login for " + name + "</h2><p>Someone is trying to log into your account, and we want to verify if it's you or not.</p><br><ul><li>Name: " + name + "</li><li>Location: " + location + "</li><li>Device: " + session.device.agent + "</li></ul><br><p>Please enter this code into your app: <b>" + session.verificationCode + "</b></p><p>If this is not you, please change your password.</p>");
        return res.status(200).json({"success": "email sent"});
    });

    router.post("/approve", async (req, res) => {
        if (req.body.code == null) return res.status(403).json({"error": "no code", "message": "Invalid code."});
        const code = req.body.code.toLowerCase();
        print("received approve code: " + code);
        const session = getAuthData().sessions.find(item => item.verificationCode.toLowerCase() == code && item.active == false);
        if (session == null) return res.status(403).json({"error": "invalid code", "message": "Invalid code."});
        if (new Date(session.created).getTime() < Date.now() - 10 * 60 * 1000) return res.status(403).json({"error": "expired code", "message": "Your code has expired. Please try again."});
        print("verifying session");
        verifySession(session.id, true);
        print("success: " + session.id);
        return res.status(200).json({"success": "", "id": session.id});
    });

    // id: session
    // password: current password
    // new: new password

    router.post("/changePassword", async (req, res) => {
        if (!validateString(req.body.id) || !validateString(req.body.password) || !validateString(req.body.new)) return res.status(400).json({"error": "invalid parameters"});
        const session = getSession(req.body.id);
        if (session == null) return res.status(403).json({"error": "invalid session"});
        const user = getUserById(session.user);
        if (user == null) return res.status(403).json({"error": "invalid user"});
        if (!(await checkUser(user, req.body.password))) return res.status(403).json({"error": "invalid password"});
        await changeUserPassword(user.id, req.body.new);
        const data = getAuthData();
        data.sessions = data.sessions.filter(item => item.user != user.id || item.id == session.id);
        saveAuthData(data);
        return res.status(200).json({"success": "password reset"});
    });

    router.post("/addUser", async (req, res) => {
        if (!validateString(req.body.email) || !validateString(req.body.password) || !validateString(req.body.firstName) || !validateString(req.body.lastName)) return res.status(403).json({"error": "invalid parameters"});
        const user = await addUser(req.body.email, req.body.password, req.body.firstName, req.body.lastName);
        res.status(200).json({"message": "Your user has been created. You will need to wait for your user to be activated to use it. Your user may be removed if it is not valid."});
    }, harshlimit);

    print("generated auth routes");
    return router;
}

module.exports = {
    verify,
    routes,
    verifySocket,
    filterSessions,
    getSession,
    validateString,
    getUserByEmail,
    getUserById,
    checkUser,
    getAuthData,
    saveAuthData,
    getAuthDataAsync,
    saveAuthDataAsync,
};