const line = "----------------------------------------";
const { print, warn, log, command, buildAppCommand, getClient, getConfig, debug, version, configdir, serverdir, notfound, dotenv, stringToBool, activateSpotify, getData, saveData, reloadAllDatabases, isLocalClient, isLocalHost } = require('./localpkg.cjs');
dotenv();

const addr = '0.0.0.0';
const secure = stringToBool(process.env.HTTPS);

log('SERVER DETECTED START: SERVER STARTED AT ' + Date.now());
print(line);
print('---------- SERVER IS STARTING ----------');
print(line);

const express = require('express');
const fs = require('fs');
const http = require('http');
const https = require('https');
const path = require('path');
const cors = require('cors');
const cron = require('node-cron');
const { spawn } = require('child_process');

const app = express();
const wwwroot = path.join(path.resolve(__dirname, '..'), 'public');
const args = require('minimist')(process.argv.slice(2));

let server;
let httpsserver;

print("starting server... (https: " + secure + ")");
require('./socket').init();

try {
  getData();
} catch (e) {
  warn("getData error: " + e);
  saveData({});
}

if (!fs.existsSync(serverdir + '/data.json')) {
  print("creating data.json");
  fs.writeFileSync(serverdir + '/data.json', "{}", { flag: 'wx' });
}

if (!fs.existsSync(configdir + "/temp")) {
  print("creating temp");
  fs.mkdirSync(configdir + "/temp", { recursive: true });
}

var data = getData();
data["dashboards"] ??= {};
saveData(data);

if (secure) {
  const options = {
    cert: fs.readFileSync(path.resolve(configdir + '/cert/cert.pem')),
    key: fs.readFileSync(path.resolve(configdir + '/cert/key.pem')),
    //passphrase: fs.readFileSync(path.resolve(configdir + '/cert/pass.txt'), 'utf8').trim(),
  };

  print("setting up http server (server)...");
  server = http.createServer(app);

  print("setting up https server (httpsserver)...");
  httpsserver = https.createServer(options, app);
} else {
  print("setting up http server (server)...");
  server = http.createServer(app);
}

require("dotenv").config();
print("server (version: " + version + ") (debug: " + debug + ") (wwwroot: " + wwwroot + ")");

app.use(cors());
app.options('*', cors());

app.options('*', (req, res) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.sendStatus(200);
});

app.use(cmiddle);
app.use(cparser);
app.use(verify);

print("generating routes...");

app.use(logger("after verify", "1", true));
app.use('/api', require('./api.js'));
app.use(express.static(wwwroot));
app.use(notfound);

function logger(service, log, progress = true) {
  return (req, res, next) => {
    print("router.logger: " + service + ": " + log + " (" + (progress == false ? "not " : "") + "continuing)");
    if (progress) {
      next();
    } else {
      return res.status(403).json({"error": "stopped by logger"});
    }
  };
}

function verify(req, res, next) {
  const accessCode = req.headers["authentication"];
  const password = req.headers["password"];
  const override = args["override-verify"] == true;
  const isLocal = isLocalHost(req);
  const status = (accessCode == process.env.ACCESS_CODE && password == process.env.PASSWORD) || override || isLocal;
  const log = "verify client: (access code match: " + (accessCode == process.env.ACCESS_CODE) + ") (password match: " + (password == process.env.PASSWORD) + ") (client vs server: " + accessCode + " : " + process.env.ACCESS_CODE + ") (override: " + override + ") (isLocal: " + isLocal + ") = " + status;

  if (status) {
    print(log);
    next();
  } else {
    warn(log);
    res.status(403).json({"error":"access denied", "code": "ATV x2"});
  }
}

async function cmiddle(req, res, next) {
  const client = getClient(req);
  const launch = getConfig().server;
  const startTime = Date.now();
  const stringifiedIn = "incoming request: " + req.method + " " + req.url + "\nheaders: " + JSON.stringify(req.headers) + "\nbody: " + JSON.stringify(req.body ?? {});
  const stringifiedOut= "outgoing serve: " + req.method + " " + req.url + "\nheaders: " + JSON.stringify(res.getHeaders());

  print("middleware called");
  print("request: " + req.method + ":" + req.protocol + " from " + client);
  log("incoming request from " + client + ": " + stringifiedIn);

  if (secure === true) {
    print("secure connection");
  } else {
    print("insecure connection");
  }

  res.on('finish', () => {
    const duration = Date.now() - startTime;
    log("outgoing serve: " + res.statusCode + " (" + duration + "): " + stringifiedOut);
  });

  if ("error" in launch) {
    print('middleware: launch error: ' + launch.error);
    return res.status(500).json({
      error: "internal server error",
    });
  }

  if (launch.enable.enabled === true) {
    print("server is enabled");
  } else {
    print("launch disabled: " + launch.enable.reason);
    res.status(403).json({
      error: "server unavailable",
      reason: launch.server.reason,
    });
    return;
  }

  res.setHeader('X-Debug-Mode', debug);
  res.setHeader('C-Author', 'Calebh101');
  res.setHeader('C-Services', 'announcer');
  res.setHeader('C-Engines', 'localpkg');
  res.setHeader('C-Processes', 'CParser, CMiddle, CAdmin');

  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    });
    res.end();
    return;
  }

  print("checking body: " + typeof req.body);
  if (req.headers['content-type'] === 'application/json' && !req.body) {
    print("no body");
    req.body = {};
  }

  print("continuing request...");
  next();
}

async function cparser(req, res, next) {
  print("starting cparser...");
  try {
    const type = req.headers['content-type'];
    let body = '';
    req.on('data', (chunk) => {
      print("received raw body chunk");
      body += chunk.toString();
    });

    req.on('end', () => {
      try {
        if (body !== '') {
          print("received body from req.data: " + type);
          if (type.includes("application/json")) {
            req.body = JSON.parse(body);
            const pattern = /,\s*([\]}])/g;
            const match = body.match(pattern);

            if (match) {
              print("invalid body");
              return res.status(400).json({ error: 'invalid body' });
            } else {
              print("valid body");
            }
          } else if (type === "text/plain") {
            req.body = {"body": body};
          } else {
            print("unknown type: " + type);
            req.body = body;
          }
        } else {
          print("received body from req.query");
          req.body = req.query ?? {};
        }

        if (req.body == null) {
            req.body = {};
        }

        next();
      } catch (e) {
        print("parse error (1): " + e);
        return res.status(400).json({ error: 'invalid body' });
      }
    });
  } catch (e) {
    print("parse error (0): " + e);
    return res.status(400).json({ error: 'invalid body' });
  }
}

listen(80);
listen(443, true);

function listen(port, secure = false) {
  (secure ? httpsserver : server).listen(port, addr, () => {
    const protocol = (secure ? "https" : "http");
    print(`${protocol} server running on ${protocol}://localhost:${port} for ${addr}`);
  });  
}

server.on('close', () => {
  print("closed server");
});

print("server: " + typeof server);
activateSpotify();
reloadAllDatabases();

if (getConfig().nightmode.enable == true) {
  const times = getConfig().nightmode;
  print("starting node-cron jobs... (times: " + JSON.stringify(times) + ")");

  cron.schedule(times.start.minute + ' ' + times.start.hour + ' * * *', () => {
    nightmodeCronJob("on");
  });

  cron.schedule(times.end.minute + ' ' + times.end.hour + ' * * *', () => {
    nightmodeCronJob("off");
  });
} else {
  print("skipping node-cron jobs");
}

function nightmodeCronJob(status) {
  try {
    const cmd = buildAppCommand('nightmode_' + status);
    print("cron: nightmode." + status + " activated (cmd: " + cmd + ")");

    command(null, cmd, 'nightmode.schedule.' + status, (stdout) => {
      print("cron: nightmode." + status + " stdout: " + stdout.trim());
    }, true, false);
  } catch (e) {
    warn("cron: nightmode." + status + " error: " + e);
  }
}

cron.schedule("0 * * * *", () => {
  reloadAllDatabases();
});

print("noip-duc: starting noip-duc...");
const noipprocess = spawn("noip-duc", ["-g", process.env.NOIPHOST, "--username", process.env.NOIPKEY, "--password", process.env.NOIPPASS], {detached: false});
  
noipprocess.stdout.on('data', (data) => {
  log("noip-duc: stdout: " + data.toString().trim());
});
  
noipprocess.stderr.on('data', (data) => {
  log("noip-duc: stderr: " + data.toString().trim());
});

module.exports = {
  server,
};
