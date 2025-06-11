const fs = require('fs');
const fsPromise = require('fs').promises;
const Path = require('path');
const { exec, spawn } = require('child_process');
const { Client } = require('@notionhq/client');
const nodemailer = require('nodemailer');
const axios = require('axios');

const configdir = "/var/www/home";
const serverdir = configdir + "/server";

// get environmental variables
dotenv();
let ipAddress;

const version = "1.1.1A";
const debug = stringToBool(process.env.DEBUG ?? 0);

const notion = new Client({
  auth: process.env.NOTION_TOKEN,
});

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.EMAIL,
    pass: process.env.EMAILPASS,
  },
});

function print(input, add) {
    add ??= true;
    console.log("LOG " + new Date().toISOString() + " (" + typeof input + "): ", input);
    if (add) {
      log(input);
    }
}

function warn(input, add) {
    add ??= true;
    console.log("\x1b[33mWARN " + new Date().toISOString() + " (" + typeof input + "): ", input + "\x1b[0m");
    if (add) {
      log("WARNING: " + input);
    }
}

function log(input) {
    var line = "-----------------------------------------";
    var inputS;
  
    if (isMultiline(input)) {
      inputS = line + "\n" + input + "\n" + line;
    } else {
      inputS = input;
    }
  
    /*if (verbose) {
      console.log("LOG: " + input);
    }*/
  
    /*fs.appendFile('debug.log', inputS.split('\n').map(line => "LOG " + new Date().toISOString() + ': ' + line).join('\n') + '\n', (error) => {
      if (error) {
        console.error('log failed: ' + error);
      }
    });*/
}

function isMultiline(str) {
  return /\r?\n/.test(str);
}

function getClient(req) {
  if (!req) {
    print("getClient: req is null or undefined");
  }
  var client = req.ip || req.connection.remoteAddress;
  if (client === "127.0.0.1" && req.body) {
    return req.body.client ?? client;
  }
  return client;
}

function isLocalClient(req) {
  const ip = getClient(req);
  if (!ip) return false;

  // Remove IPv6 prefix if present (e.g., "::ffff:192.168.1.10")
  if (ip.includes("::ffff:")) {
    ip = ip.split("::ffff:")[1];
  }

  const parts = ip.split('.').map(Number);

  return (
    // 10.0.0.0 – 10.255.255.255
    (parts[0] === 10) ||
    // 172.16.0.0 – 172.31.255.255
    (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) ||
    // 192.168.0.0 – 192.168.255.255
    (parts[0] === 192 && parts[1] === 168) ||
    // Loopback
    (ip === "127.0.0.1" || ip === "::1")
  );
}

function getConfig() {
  try {
    const path = Path.resolve(configdir + '/config.json');
    print("retrieving launch data... (path: " + path + ")");
    const data = fs.readFileSync(path, 'utf8');
    const launch = JSON.parse(data);
    return launch;
  } catch (e) {
    print("getConfig: launch error: " + e);
    return {"error": e};
  }
}

function notfound(req, res, next) {
  res.status(404).json({
    error: 'cannot ' + req.method + " " + req.url,
  });
}

function dotenv() {
  require('dotenv').config({path: configdir + '/.env'});
}

function stringToBool(bool) {
  bool = bool.toLowerCase();
  if (bool === "true" || bool === 1 || bool === "1") {
    return true;
  } else {
    return false;
  }
}

function getData() {
    const data = fs.readFileSync(serverdir + '/data.json', 'utf8');
    return JSON.parse(data);
}

function saveData(data) {
	fs.writeFileSync(serverdir + '/data.json', JSON.stringify(data, null, 4));
}

function moveToTop(array, key, value) {
  const index = array.findIndex(item => item[key] === value);
  
  if (index > -1) {
    const [item] = array.splice(index, 1); // Remove the found item
    array.unshift(item); // Move it to the top
  }

  return array;
}

function activateSpotify(spotify) {
  var spotify = true;

  process.argv.slice(2).forEach(arg => {
    if (arg.trim() == "--no-spotify") {
      spotify = false;
    }
  });

  if (spotify) {
    const spotifydevicename = (debug ? "DEBUG: " : "") + "Home Speaker";
    print("loading spotifyd... (name: " + spotifydevicename + ")");
    const process = spawn(configdir + "/spotify/spotifyd", ["--device-name", spotifydevicename, "--device-type", "speaker", "--no-daemon", "--use-mpris"], {detached: false});
  
    process.stderr.on('data', (data) => {
      warn("spotifyd: stderr: " + data);
    });
  } else {
    print("spotify disabled");
  }
}

async function command(res, command, service = "server", callback, ignoreErrors = false, quiet = false, doNotAutoOutputStderr = false) {
  if (quiet == false) {
  	print("running command: " + command);
  }

  return new Promise((resolve, reject) => {
    exec(command, (error, stdout, stderr) => {
      if (error && !ignoreErrors) {
        warn(`${service} exec error: ${error.message}`);
        res.status(500).json({"error": "internal server error", "type": "exec"});
        return;
      } else if (stderr && !ignoreErrors) {
        warn(`${service} stderr: ${stderr}`);
        res.status(500).json({"error": "internal server error", "type": "std"});
        return;
      }

      var out = stdout;

      if (out == "" && doNotAutoOutputStderr) {
        out = stderr;
      }

      if (quiet == false) {
        print(`${service} stdout: ${out.trim()}`);
      }

      if (callback) {
        callback(out);
      } else {
        res.status(200).json({"success": service});
      }

      resolve(out);
      return;
    });
  });
}

function buildAppCommand(command) {
	return `echo "${command}" | nc localhost 8020 || echo '{"error":"unavailable"}'`;
}

function parseNumber(str) {
  const num = Number(str);
  return !isNaN(num) && str.trim() !== '' ? num : null;
}

function sendEmail(to, subject, html) {
  const recipients = [to, ...process.env.CONTACT.split(",")];
  print("email loading: " + recipients.join(", "));

  const mailOptions = {
    from: process.env.EMAIL,
    to: recipients,
    subject: subject,
    html: html,
  };
  
  try {
    transporter.sendMail(mailOptions, (error, info) => {
      if (error) throw new Error(error);
      print("email sent: " + recipients.join(", "));
    });
  } catch (e) {
    print("email error: " + e);
  }
}

async function reloadAllDatabases() {
  try {
    print("database reload: start");
    await Promise.all([refreshAnnouncements(), refreshContacts(), refreshDevices(), refreshTvs()]);
    const data = getData();
    data.lastRefreshed = new Date().toISOString();
    saveData(data);
    return true;
  } catch (e) {
    warn("database reload: error: " + e);
    return false;
  }
}

async function refreshTvs() {
  print("refreshing devices...");
  var results = [];

  var response = await notion.databases.query({
    database_id: process.env.TVS_DATABASE,
  });

  results.push(...response.results);

  // pagination
  while (response.has_more) {
    response = await notion.databases.query({
      database_id: databaseId,
      start_cursor: response.next_cursor,
    });
    results.push(...response.results);
  }

  const devices = await Promise.all(results.map(async (page, i) => {
    function getStringProperty(property) {
      return page.properties[property][page.properties[property].type][0].plain_text;
    }

    function getSelectProperty(property) {
      return page.properties[property].select.name;
    }

    function getNumberProperty(property) {
      return page.properties[property].number;
    }

    const name = getStringProperty("Name");
    const id = getStringProperty("ID");
    const type = getSelectProperty("Type");
    const ip = getStringProperty("IP Address");
    const port = getNumberProperty("Port");
    const mac = getStringProperty("MAC Address");
    const auth = getStringProperty("Authorization Code");

    return {
      "name": name,
      "id": id,
      "type": type,
      "ip": ip,
      "port": port,
      "mac": mac,
      "code": auth,
    };
  }));

  print("saved " + 0 + " tvs");
  fs.writeFileSync(serverdir + "/tvs.json", JSON.stringify({"tvs": devices}));
}

async function refreshDevices() {
  print("refreshing devices...");
  var results = [];
  var rooms = [];

  var response = await notion.databases.query({
    database_id: process.env.DEVICES_DATABASE,
  });

  results.push(...response.results);

  // pagination
  while (response.has_more) {
    response = await notion.databases.query({
      database_id: databaseId,
      start_cursor: response.next_cursor,
    });
    results.push(...response.results);
  }

  const devices = await Promise.all(results.map(async (page, i) => {
    function getSelectProperty(property) {
      return page.properties[property].select.name;
    }

    function getStringProperty(property) {
      return page.properties[property][page.properties[property].type][0].plain_text;
    }

    const type = getSelectProperty("Type");
    const room = getSelectProperty("Room");
    const name = getStringProperty("Name");
    const id = getStringProperty("ID");
    const index = rooms.findIndex(item => item.name === name);

    const device = {
      "name": name,
      "id": id,
      "type": type,
    };

    if (index === -1) {
      rooms.push({"name": room, "id": room.toLowerCase().replace(/[^a-zA-Z0-9 ]/g, '').replaceAll(" ", "-"), "devices": [device]});
    } else {
      rooms[index].devices.push(device);
    }

    return device;
  }));

  print("saved " + rooms.length + " rooms and " + devices.length + " devices");
  fs.writeFileSync(serverdir + "/house.json", JSON.stringify({"rooms": rooms}));
}

async function refreshAnnouncements() {
  print("refreshing announcements...");
  var results = [];

  var response = await notion.databases.query({
    database_id: process.env.ANNOUNCEMENTS_DATABASE,
  });

  results.push(...response.results);

  // pagination
  while (response.has_more) {
    response = await notion.databases.query({
      database_id: databaseId,
      start_cursor: response.next_cursor,
    });
    results.push(...response.results);
  }

  const announcements = await Promise.all(results.map(async (page, index) => {
    const item = page.properties;
    const title = item.Title.title[0].text.content;
    const date = new Date(item.Date.date.start).toISOString();
    const expires = item.Expires.number;
  
    const description = await (async () => {
      try {
        const response = await notion.blocks.children.list({ block_id: page.id });
        const desc = response.results.map(item => {
          if (item.type == "paragraph") {
            return item.paragraph.rich_text.map(richText => richText.plain_text).join('\n');
          } else if (item.type = "bulleted_list_item") {
            return "- " + item.bulleted_list_item.rich_text.map(richText => richText.plain_text).join('\n');
          } else {
            throw new Error("Unhandled block type: " + item.type);
          }
        }).join('\n');
        return desc;
      } catch (e) {
        warn("announcements.page error: " + e);
        return "Error: " + e;
      }
    })();
  
    return {
      title,
      description,
      date,
      expires,
    };
  }));

  var data = getData();
  data.announcements = announcements.sort((a, b) => new Date(b.date) - new Date(a.date));
  saveData(data);
  print("saved " + announcements.length + " announcements");
}

async function refreshContacts() {
  print("refreshing announcements...");
  var results = [];
  var contacts = [];

  var response = await notion.databases.query({
    database_id: process.env.CONTACTS_DATABASE,
  });

  results.push(...response.results);

  // pagination
  while (response.has_more) {
    response = await notion.databases.query({
      database_id: databaseId,
      start_cursor: response.next_cursor,
    });
    results.push(...response.results);
  }

  results.forEach((page, index) => {
    const item = results[index].properties;
    const firstname = item["First Name"].title[0].text.content;
    const lastname = item["Last Name"].rich_text[0].text.content;
    const birthday = item.Birthday.date ? new Date(item.Birthday.date.start).toISOString() : null;

    contacts.push({
      name: {
        first: firstname,
        last: lastname,
      },
      birthday,
    });
  });

  var data = getData();
  data.contacts = contacts;
  saveData(data);
  print("saved " + contacts.length + " contacts");
}

function isLocalHost(req) {
  var client = getClient(req);
  return client == "localhost" || client == "127.0.0.1" || client == "::1";
}

function updateIp() {
  print("finding ip...");
  ipAddress = null;

  axios.get('https://api.ipify.org?format=json').then(res => {
    const data = res.data;
    print("got ip data: " + JSON.stringify(data));
    ipAddress = data.ip;
  }).catch(e => {
    warn("couldn't get ip: " + e);
  });
}

function getIp() {
  return ipAddress;
}

module.exports = {
  version,
  debug,
  configdir,
  serverdir,
  print,
  warn,
  log,
  getClient,
  isLocalClient,
  isMultiline,
  getConfig,
  notfound,
  dotenv,
  stringToBool,
  getData,
  saveData,
  moveToTop,
  activateSpotify,
  command,
  buildAppCommand,
  reloadAllDatabases,
  parseNumber,
  isLocalHost,
  sendEmail,
  updateIp,
  getIp,
};