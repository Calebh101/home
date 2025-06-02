const { print, warn, log, debug, notfound, dotenv, getData, saveData, getConfig, getClient, configdir, buildAppCommand, command, reloadAllDatabases, parseNumber, version } = require('./localpkg.cjs');
const express = require('express');
const router = express.Router();
const fs = require('fs');
const { getState, getSocketPort, controller } = require('./socket');
const nodemailer = require('nodemailer');
const axios = require('axios');
const Path = require('path');
const vizio = require('./vizio.js');

var minbrightness = 5;
var maxvolume = getConfig().limits.maxvolume;
var dexcomSessionToken;
var fireplaces = getConfig().fireplaces;

const tvs = JSON.parse(fs.readFileSync(Path.join(__dirname, 'tvs.json')));
const tvapps = JSON.parse(fs.readFileSync(Path.join(__dirname, 'tv-apps.json')));
const tvdata = JSON.parse(fs.readFileSync(Path.join(__dirname, 'tv-data.json')));
const house = JSON.parse(fs.readFileSync(Path.join(__dirname, 'house.json')));

// Custom .env loader
dotenv();

function refreshapp() {
	command(null, buildAppCommand("refresh"), "server.app.refresh", () => {}, true);
}

function verifyAdmin(req) {
	if (req == null) throw new Error("verifyAdmin: req cannot be null.");
	var status = req.body.password == process.env.ADMIN_CODE;
	print("admin status: " + status);
	return status;
}

// system
(() => {
	router.post("/check", (req, res) => {
		res.status(200).json({});
	});

	router.post("/system/admin/check", (req, res) => {
		res.status(200).json({"status": verifyAdmin(req)});
	});

	router.post("/system/about", (req, res) => {
		var serverver = version;
		var configver = getConfig().version;

		command(res, `awk '{printf "%s ", $2} END {print ""}' /etc/issue`, 'system.about.version.system', (stdout) => {
			var systemver = stdout.trim();
			var countlinescommand = configdir + "/build/countlines --json";
			print("countlines command: " + countlinescommand);

			command(res, countlinescommand, "system.about.countlines", (stdout) => {
				var countlinesdump = JSON.parse(stdout.trim());
				command(res, buildAppCommand('info_dump'), 'app.infodump', (stdout) => {
					var infodump = JSON.parse(stdout.trim());
					var data = {
						"version": {
							"server": serverver,
							"config": configver,
							"system": systemver,
							"app": ("error" in infodump) ? null : infodump.version.app,
						},
						"code": countlinesdump,
					};

					res.status(200).json(data);
				});
			});
		});
	});

	router.post("/system/version/app", (req, res) => {
		command(res, buildAppCommand('info_dump'), 'app.infodump', (stdout) => {
			var infodump = JSON.parse(stdout.trim());
			var data = {"version": ("error" in infodump) ? null : infodump.version.app};
			res.status(200).json(data);
		});
	});

	router.post("/system/state", async (req, res) => {
		res.status(200).json(await getState());
	});

	router.post("/system/status", (req, res) => {
		command(res, buildAppCommand('state_dump'), 'system.status.app.statedump', async (stdout) => {
			var appstate = JSON.parse(stdout.trim());
			var app = false;

			if ("error" in appstate) {
				app = false;
			} else {
				app = true;
			}

			res.status(200).json({
				"app": app,
				"server": (await getConfig().server.enable.enabled),
				"socket": {
					"port": getSocketPort(),
				},
			});
		});
	});

	router.post("/system/limits", (req, res) => {
		const config = getConfig();

		res.status(200).json({
			"brightness": {
				"min": minbrightness,
				"max": 100,
			},
			"volume": {
				"min": 0,
				"max": maxvolume,
			},
			"nightmode": {
				"start": config.nightmode.start,
				"end": config.nightmode.end,
			},
			"glucose": config.glucose,
		});
	});

	router.post("/system/shutdown", (req, res) => {
		if (!verifyAdmin(req)) return res.status(403).json({"error": "invalid password"});
		const client = getClient(req);
		const shutdowndelay = getConfig().server.shutdowndelay ?? 30;

		warn("WARNING: SHUTDOWN SIGNALED BY CLIENT: " + client);
		print("To cancel shutdown, run \"pkill sleep\" within " + shutdowndelay + " seconds.");

		fs.appendFileSync('/var/log/homeserver.log', 'Shutdown signaled by client: ' + client + "\n");
		res.status(200).json({"success": "shutdown signaled", "seconds": shutdowndelay});

		if (!debug) {
			command(null, `${buildAppCommand("shutdown " + shutdowndelay)} && nohup bash -c "sleep ${shutdowndelay} && systemctl poweroff" >/dev/null 2>&1 &`, "system.shutdown", (stdout) => {});
			process.exit(0);
		} else {
			print("shutdown simulated");
		}
	});

	router.post("/system/suspend", (req, res) => {
		if (!verifyAdmin(req)) return res.status(403).json({"error": "invalid password"});
		command(res, "systemctl suspend", "system.suspend");
	});

	router.post("/system/command", (req, res) => {
		if (!verifyAdmin(req)) return res.status(403).json({"error": "invalid password"});
		const cmd = req.body.command;

		if (!cmd) {
			return res.status(400).json({"error": "command required"});
		}

		if (!debug) {
			return res.status(403).json({"error": "commands disabled"});
		}

		command(res, cmd, "system.command.custom", (stdout) => {
			return res.status(200).json({"stdout": stdout});
		});
	});

	router.post("/system/update", async (req, res) => {
		if (!verifyAdmin(req)) return res.status(403).json({"error": "invalid password"});
		command(null, configdir + "/tools/updatehost.sh -a", "system.update", () => {
			print("update started");
		});
		res.status(200).json({"success": "restarting"});
		process.exit(0);
	});

	router.post("/system/app/close", (req, res) => {
		command(res, buildAppCommand("exit"), "system.app.close");
	});

	router.post('/system/refresh', async (req, res) => {
		if (await reloadAllDatabases()) {
			res.status(200).json({"success": "refreshed"});
		} else {
			res.status(500).json({"error": "internal server error"});
		}
	});
})();

// alerts
(() => {
	router.post("/alert/dismiss", (req, res) => {
		const id = req.body.id;
		if (id == null) return res.status(400).json({"error": "invalid id"});
		command(res, buildAppCommand("dismiss_alert " + id), "alert.dismiss");
	});

	router.post("/alert/send", (req, res) => {
		const { message, severity } = req.body;
		const recipients = process.env.CONTACT.split(',');
		const from = process.env.EMAIL;
		const emailPass = process.env.EMAILPASS;

		print("sending email from " + from);

		const subject = "Home Server Critical Alert";
		const html = "<h2>Critical Alert from Home Server</h2><p>Severity: " + severity + "</p><p>Message: " + message + "</p>";

		const transporter = nodemailer.createTransport({
			service: 'gmail',
			auth: {
				user: from,
				pass: emailPass,
			},
		});

		const mailOptions = {
			from: from,
			to: recipients.join(','),
			subject: subject,
			html: html,
		};
		
		try {
			res.status(200).json({"success": "email sending"});
			transporter.sendMail(mailOptions, (error, info) => {
				if (error) {
					throw new Error(error);
				}
			});
		} catch (e) {
			warn("email error: " + e);
			res.status(500).json({"error": "internal server error"});
		}
	});
})();

// global
(() => {
	router.post("/weather", async (req, res) => {
		try {
			const zip = req.body.zip || process.env.ZIP;
			print("global.weather: requesting for " + zip);
			const response = await fetch("https://api.weatherapi.com/v1/forecast.json?key=" + process.env.WEATHERAPI_KEY + "&q=" + zip + "&days=3&aqi=no&alerts=no");
    
			if (!response.ok) {
				throw new Error(`HTTP status: ${response.status}`);
			}

			const data = await response.json();
			return res.status(200).json({"data": data});
		} catch (e) {
			warn("global.weather: " + e);
			return res.status(500).json({"error": "internal server error"});
		}
	});

	router.post("/news", async (req, res) => {
		try {
			const response = await fetch("https://newsapi.org/v2/top-headlines?country=us&apiKey=" + process.env.NEWSAPI_KEY);
    
			if (!response.ok) {
				throw new Error(`HTTP status: ${response.status}`);
			}

			const data = await response.json();
			return res.status(200).json({"data": data});
		} catch (e) {
			warn("global.weather: " + e);
			return res.status(500).json({"error": "internal server error"});
		}
	});
})();

// announce messages
(() => {
	const { handle } = require('./services/announcer');

	router.post("/announce", async (req, res) => {
		handle(req, res);
	});

	router.post("/announce/delete", async (req, res) => {
		const { message } = req.body;
		if (!message) {
			return res.status(400).json({"error": "message required"});
		}

		const config = getData();
		if (!config.announcedmessages.some(item => item.message === message)) {
			return res.status(404).json({"error": "message not found"});
		} else {
			config.announcedmessages = config.announcedmessages.filter(item => item.message !== message);
			saveData(config);
			return res.status(200).json({"success": "message deleted"});
		}
	});

	router.post("/announce/get", async (req, res) => {
		const data = getData().announcedmessages;
		res.status(200).json({"messages": data});
	});
})();

// theme
(() => {
	function setTheme(res, theme) {
		command(res, buildAppCommand('set_theme ' + (theme == "dark" ? 1 : 0)), "theme.set." + theme);
	}

	router.post("/theme/light", (req, res) => {
		setTheme(res, 'light');
	});

	router.post("/theme/dark", (req, res) => {
		setTheme(res, 'dark');
	});
})();

// announcements
(() => {
	router.post("/announcements/get", async (req, res) => {
		const data = getData().announcements;
		res.status(200).json({"announcements": data});
	});
})();

// screen
(() => {
	router.post("/screen/reset", async (req, res) => {
		reset();
		res.status(200).json({"success": "screen state reset"});
	});

	router.post("/screen/on", async (req, res) => {
		command(res, "export DISPLAY=:0 && xset dpms force on && xset s reset", "screen.on");
	});

	router.post("/screen/off", async (req, res) => {
		command(res, "export DISPLAY=:0 && xset dpms force off", "screen.off");
	});

	function reset(service = 'screen.reset') {
		command(res, 'DISPLAY=:0 xset dpms 300 600 900', service);
	}
})();

// volume
(() => {
	router.post("/volume/set", (req, res) => {
		const volume = req.body.volume;

		if (!isInt(volume)) {
			return res.status(400).json({"error": "invalid volume", "message": "not a valid integer between 0 and 100"});
		}

		if (volume > maxvolume) {
			return res.status(400).json({"error": "invalid volume", "message": "volume cannot be greater than " + maxvolume});
		}

		command(res, "amixer set Master " + volume + "%", "volume.set");
	});
})();

// brightness
(() => {
	router.post("/brightness/set", (req, res) => {
		const brightness = req.body.brightness;

		if (!isInt(brightness)) {
			return res.status(400).json({"error": "invalid brightness", "message": "not a valid integer between 0 and 100"});
		}

		if (brightness < minbrightness) {
			return res.status(400).json({"error": "invalid brightness", "message": "brightness cannot be less than " + minbrightness});
		}

		command(res, "sudo brightnessctl set " + brightness + "%", "brightness.set");
	});
})();

// nightmode
(() => {
	router.post("/nightmode/on", async (req, res) => {
		command(res, buildAppCommand('nightmode_on'), 'nightmode.on');
	});

	router.post("/nightmode/off", async (req, res) => {
		command(res, buildAppCommand('nightmode_off'), 'nightmode.off');
	});
})();

// dexcom
(() => {
	router.post("/dexcom/app/open", async (req, res) => {
		command(res, buildAppCommand('glucose_on'), 'dexcom.app.on');
	});

	router.post("/dexcom/app/close", async (req, res) => {
		command(res, buildAppCommand('glucose_off'), 'dexcom.app.off');
	});

	router.post("/dexcom/app/refresh", async (req, res) => {
		command(res, buildAppCommand('glucose_reload'), 'dexcom.refresh');
	});

	router.post("/dexcom/get", async (req, res) => {
		print("starting dexcom.get");
		var data;

		try {
			data = await dexcom();
		} catch (e) {
			warn("dexcom get error: " + e);
			return res.status(500).json({"error": "internal server error"});
		}

		if ("error" in data) {
			return res.status(500).json(data);
		} else {
			return res.status(200).json(data);
		}
	});

	async function dexcom(minutes = 185) {
		print("dexcom: finding username and password");
		const username = process.env.DEXCOM_USERNAME;
		const password = process.env.DEXCOM_PASSWORD;
	
		if (username == null || password == null) {
			return {"error": "invalid credentials", "message": "credential(s) are null", status: 400};
		}
	
		const response = await fetch(
			'https://share2.dexcom.com/ShareWebServices/Services/Publisher/ReadPublisherLatestGlucoseValues',
			{
				method: 'POST',
				headers: {
					"Content-Type": "application/json",
				},
				body: JSON.stringify({
					"sessionId": dexcomSessionToken ?? "null",
					"minutes": minutes + 5,
					"maxCount": minutes / 5,
				}),
			},
		);
	
		if (response.status !== 200) {
			print("refreshing session token... (code: " + response.status + ") (response: " + (await response.text()) + ")");
			const applicationId = process.env.DEXCOM_APPLICATION;

			const userId = await loginShare(username, password, applicationId);
			const accountId = (await userId.text()).replaceAll("\"", "");
	
			if (userId.status !== 200) {
				print("error: " + userId.status);
				return {"error": "unauthorized", "message": "user credentials are incorrect", "status": 403};
			}
	
			const refresh = await fetch(
				"https://share2.dexcom.com/ShareWebServices/Services/General/LoginPublisherAccountById",
				{
					method: 'POST',
					headers: {
						'Content-Type': 'application/json',
					},
					body: JSON.stringify({
						"accountId": accountId,
						"password": password,
						"applicationId": applicationId,
					}),
				},
			);
	
			const body = {"token": (await refresh.text()).replaceAll("\"", "")};
			print("refresh.token response: " + JSON.stringify(body));
	
			if (refresh.status == 200) {
				dexcomSessionToken = body.token;
				print("retrying...");
				return await dexcom();
			} else {
				return {"error": "unauthorized", "message": "user has revoked permissions", code: 403};
			}
		}
	
		const data = await response.json();
		print("found data: " + typeof response + ":" + typeof data);
		return {data};
	}

	async function loginShare(username, password, application) {
		return await fetch(
			"https://share2.dexcom.com/ShareWebServices/Services/General/AuthenticatePublisherAccount",
			{
				method: 'POST',
				headers: {
					'Content-Type': 'application/json',
				},
				body: JSON.stringify({
					"accountName": username,
					"password": password,
					"applicationId": application,
				}),
			},
		);
	}
})();

// internet
(() => {
	function parsenmcli(input) {
		print("parsing nmcli output...");
		const lines = input.split('\n');
		const result = {};
	
		lines.forEach(line => {
			if (line.trim()) {
				const [key, value] = line.split(':', 2).map(part => part.trim());
				const keys = key.split('.');
				let current = result;
	
				keys.forEach((part, index) => {
					try {
						if (index === keys.length - 1) {
							if (keys[index] == "BARS") {
								current[part] = value.length;
							} else {
								if (value.replaceAll("(guessed)", "").trim() == "yes") {
									current[part] = true;
								} else if (value.replaceAll("(guessed)", "").trim() == "no") {
									current[part] = false;
								} else {
									current[part] = parseNumber(value) ?? value;
								}
							}
						} else {
							current[part] = current[part] || {};
							current = current[part];
						}
					} catch (e) {
						warn("key error (type: 1) (" + part + " at " + index + "): " + e);
					}
				});
			}
		});

		function parseDHCP(type) {
			print("parsing DHCP: " + type);
			var parsedtype = type + "-parsed";
			result[parsedtype] = {};

			Object.keys(result[type]).forEach(key => {
				try {
					var values = result[type][key].split(" = ");
					var value = values.slice(1).join(" = ");
					result[parsedtype][values[0]] = parseNumber(value) ?? value;
				} catch (e) {
					warn("key error (type: 2) (" + key + "): " + e);
				}
			});

			print("parsed DHCP: " + parsedtype);
			result[type] = undefined;
		}

		parseDHCP("DHCP4");
		parseDHCP("DHCP6");

		print("parse complete");
		return result;
	}

	router.post("/internet/test", async (req, res) => {
		print("starting internet test");
		var nmclioutput;
		var nmcli;
		var speedtestout;

		print("writing headers...");
		res.setHeader('Content-Type', 'text/event-stream');
		res.setHeader('Cache-Control', 'no-cache');
		res.setHeader('Connection', 'keep-alive');

		function status(status) {
			res.write(JSON.stringify({"status": status, "timestamp": new Date().toISOString()}));
		}

		function err(message) {
			res.write(JSON.stringify({"status": -1, "timestamp": new Date().toISOString(), "error": message}));
		}

		try {
			print("initiating...");

			try {
				await command(null, `nmcli -f all -t device show ${process.env.WIFI_DEVICE}`, "internet.test.nmcli", (stdout) => {
					print("received nmcli output");
					nmclioutput = stdout.trim();
				}, true, true);

				nmcli = parsenmcli(nmclioutput);
				print("nmcli successful");
			} catch (e) {
				warn("nmcli error: " + e);
				nmcli = null;
			}

			status(1); // running network speed test
			print("starting speedtest...");

			await command(null, buildAppCommand("speedtest"), "internet.test.app.speedtest", (stdout) => {
				speedtestout = JSON.parse(stdout);
			}, true, true);

			if (speedtestout.error == true) {
				warn("speedtestout error (retrying): " + speedtestout.error);
				await command(null, buildAppCommand("speedtest"), "internet.test.app.speedtest.retry", (stdout) => {
					speedtestout = JSON.parse(stdout);
				}, true, true);
			}

			if (speedtestout.error == true) {
				warn("speedtestout error (failed): " + speedtestout.error);
				speedtestout = null;
			}

			res.write(JSON.stringify({
				"status": 0,
				"timestamp": new Date().toISOString(),
				"result": {
					"speedtest": speedtestout,
					"status": nmcli,
				},
			}));
		} catch (e) {
			warn("internet test error: " + e);
			err("internal server error");
		}

		print("internet test complete");
		res.end();
	});

	router.post("/internet/report/speedtest", (req, res) => {
		warn("internet: report: speedtest: " + req.body.error);
		res.status(200).json({"success": "error reported"});
	});

	router.post("/internet/router", async (req, res) => {
		print("starting router check");
		var response = await ping("http://192.168.0.1");
		res.status(200).json(response);
	});

	async function ping(url) {
		print(`ping start: ${url}`);
		const start = Date.now();
	  
		try {
			const response = await axios.get(url, { timeout: 10000, validateStatus: () => true });
			const elapsed = Date.now() - start;
			print(`ping success: ${url}`);

			if (response.status >= 500) {
				throw new Error(`HTTP statuscode ${response.status}`);
			}
		
			return {
				status: true,
				host: url,
				elapsed: elapsed,
				error: null,
			};
		} catch (e) {
			const elapsed = Date.now() - start;
			warn(`ping connect error: ${e.message}`);
		
			return {
				status: false,
				host: url,
				elapsed: elapsed,
				error: e.message,
			};
		}
	}
})();

// fireplace
(() => {
	router.post("/fireplace/on", (req, res) => {
		if (!fireplaces.find(obj => obj.id === req.body.type)) res.status(400).json({"error": "invalid type"});
		command(res, buildAppCommand("fireplace_on " + (req.body.type ?? 1)), "fireplace.on");
	});

	router.post("/fireplace/off", (req, res) => {
		command(res, buildAppCommand("fireplace_off"), "fireplace.off");
	});

	router.post("/fireplace/get/available", (req, res) => {
		res.status(200).json({"fireplaces": fireplaces});
	});

	router.post("/fireplace/get/video", (req, res) => {
		const item = fireplaces.find(obj => obj.id === req.body.type);
		if (!item) res.status(400).json({"error": "invalid type"});
		const path = configdir + "/assets/fireplace/" + item.file;
		print("sending fireplace video " + path);
		res.sendFile(path);
	});

	router.post("/fireplace/sound/on", (req, res) => {
		command(res, buildAppCommand("fireplace_sound_on"), "fireplace.sound.on");
	});

	router.post("/fireplace/sound/off", (req, res) => {
		command(res, buildAppCommand("fireplace_sound_off"), "fireplace.sound.off");
	});
})();

// music
(() => {
	router.post("/music/stop", (req, res) => {
		command(res, "playerctl -p spotifyd stop", "music.stop", () => {
			res.status(200).json({"success": "sent music control"});
		}, true, false);
	});

	router.post("/music/play", (req, res) => {
		command(res, "playerctl -p spotifyd play", "music.play", () => {
			res.status(200).json({"success": "sent music control"});
		}, true, false);
	});

	router.post("/music/pause", (req, res) => {
		command(res, "playerctl -p spotifyd pause", "music.pause", () => {
			res.status(200).json({"success": "sent music control"});
		}, true, false);
	});

	router.post("/music/back", (req, res) => {
		command(res, "playerctl -p spotifyd previous", "music.back", () => {
			res.status(200).json({"success": "sent music control"});
		}, true, false);
	});

	router.post("/music/next", (req, res) => {
		command(res, "playerctl -p spotifyd next", "music.next", () => {
			res.status(200).json({"success": "sent music control"});
		}, true, false);
	});
})();

// devices - tv
(() => {
	function verify(req, type) {
		if (vizio.getTv(req.body.id) == null) {
			warn("tv verify: fail: invalid tv id: not found (type " + type + ")");
			return false;
		}

		print("tv verify: pass");
		return true;
	}

	router.post("/devices/tvs", (req, res) => {
		res.status(200).json(tvs);
	});

	router.post("/devices/tvs/vizio/settings/set", async (req, res) => {
		if (verify(req, "vizio") == false) return res.status(400).json({"error": "fail"});
		const response = await vizio.editSetting(req.body.id, req.body.name, req.body.value);
		return res.status(200).json(response);
	});

	router.post("/devices/tvs/vizio/apps/launch", async (req, res) => {
		if (verify(req, "vizio") == false) return res.status(400).json({"error": "fail"});
		const response = await vizio.launchApp(req.body.id, req.body.name);
		return res.status(200).json(response);
	});

	router.post("/devices/tvs/vizio/apps/get", async (req, res) => {
		return res.status(200).json(tvapps);
	});

	router.post("/devices/tvs/vizio/apps/favorites", async (req, res) => {
		return res.status(200).json({"apps": tvdata["favorite-apps"]});
	});

	router.post("/devices/tvs/vizio/source/devices", async (req, res) => {
		if (verify(req, "vizio") == false) return res.status(400).json({"error": "fail"});
		const response = await vizio.getDevices(req.body.id);
		return res.status(200).json(response);
	});

	router.post("/devices/tvs/vizio/source/input/change", async (req, res) => {
		if (verify(req, "vizio") == false) return res.status(400).json({"error": "fail"});
		const response = await vizio.request(req.body.id, "/menu_native/dynamic/tv_settings/devices/current_input", "PUT", {
			"REQUEST": "MODIFY",
			"VALUE": req.body.input,
			"HASHVAL": req.body.hash,
		});
		return res.status(200).json(response);
	});

	if (debug) {
		print("setting up debug tv commands...");
		router.post("/devices/tvs/vizio/command", async (req, res) => {
			if (verify(req, "vizio") == false) return res.status(400).json({"error": "fail"});
			const response = (await vizio.request(req.body.id, req.body.endpoint, req.body.method, req.body.body));
			return res.status(200).json(response);
		});
	}

	router.post("/devices/tvs/vizio/power/on", async (req, res) => {
		if (verify(req, "vizio") == false) return res.status(400).json({"error": "fail"});
		const status = (await vizio.wake(req.body.id))["status"];
		return res.status(status ? 200 : 500).json({"status": status});
	});

	router.post("/devices/tvs/vizio/power/state", async (req, res) => {
		if (verify(req, "vizio") == false) return res.status(400).json({"error": "fail"});
		const result = (await vizio.request(req.body.id, "/state/device/power_mode", "GET", null, 3000));
		if (result == null) return res.status(200).json({"status": false});
		return res.status(200).json({"status": result["ITEMS"][0]["VALUE"] == 1});
	});

	router.post("/devices/tvs/vizio/power/off", async (req, res) => {
		const result = (await vizio.request(req.body.id, "/key_command/", "PUT", {
			"KEYLIST": [{
				"CODESET": 11,
				"CODE": 0,
				"ACTION": "KEYPRESS",
			}],
		}));
		if (result == null) return res.status(200).json({"status": "offline"});
		res.status(200).json({"status": result["STATUS"]["RESULT"]});
	});

	router.post("/devices/tvs/vizio/key", async (req, res) => {
		if (verify(req, "vizio") == false || req.body.keys == null) return res.status(400).json({"error": "fail"});
		const result = (await vizio.request(req.body.id, "/key_command/", "PUT", {
			"KEYLIST": req.body.keys.map((item) => {
				return {
					"CODESET": item.set,
					"CODE": item.code,
					"ACTION": "KEYPRESS",
				};
			}),
		}));
		if (result == null) return res.status(200).json({"status": "offline"});
		res.status(200).json({"status": result["STATUS"]["RESULT"]});
	});
})();

// devices - homekit
(() => {
	var homekitFile = Path.join(__dirname, 'homekit-pairing.json');
	var homekitDataFile = Path.join(__dirname, 'homekit-data.json');
	var characteristics = JSON.parse(fs.readFileSync(Path.join(__dirname, 'homekit-characteristics.json')));

	if (!fs.existsSync(homekitFile)) {
		throw new Error("A HomeKit data file is required.");
	}

	async function refreshHomekitData(id) {
		var homekitData = JSON.parse(fs.readFileSync(homekitFile));
		var data = homekitData[id];
		var request = "/var/www/home/tools/python3.9/bin/venv/bin/python3 -m homekit.get_characteristic -f /var/www/home/server/homekit-pairing.json -a ecobee3" + characteristics[id].map(value => " -c " + value["id"]).join(" ");
		print("homekit get: " + request);
		await command(null, request, "homekit.refresh." + id, async (stdout) => {
			try {
				var data = JSON.parse(stdout);
				fs.writeFileSync(homekitDataFile, JSON.stringify({[id]: {"data": data, "lastUpdated": new Date()}}), { flag: 'w' });
			} catch (e) {
				warn("homekit.refresh.parse: " + e);
			}
		}, true, true);
		print("homekit: all clear");
		return;
	}

	function getHomekitData(id) {
		try {
			return JSON.parse(fs.readFileSync(homekitDataFile))[id];
		} catch (e) {
			warn("get homekit data: " + e);
			return null;
		}
	}

	router.post("/devices/homekit", async (req, res) => {
		return res.status(200).json({"devices": Object.keys(JSON.parse(fs.readFileSync(homekitFile)))});
	});

	router.post("/devices/homekit/:id", async (req, res) => {
		const id = req.params.id;
		await refreshHomekitData(id);
		var data = getHomekitData(id);
		print("homekit: found data");

		if (data == null) {
			return res.status(401).json({"error": "invalid id"});
		} else {
			return res.status(200).json(data);
		}
	});

	router.post("/devices/homekit/:id/set", async (req, res) => {
		const id = req.params.id;
		const {characteristic, value} = req.body;

		if (id == null || characteristic == null || value == null) {
			return res.status(400).json({"error": "fill out required fields"});
		}

		var request = "/var/www/home/tools/python3.9/bin/venv/bin/python3 -m homekit.put_characteristic -f /var/www/home/server/homekit-pairing.json -a ecobee3 -c " + characteristic + " " + value;
		print("homekit set: " + request);
		await command(res, request, "homekit." + id + ".set");
	});
})();

// devices - house
(() => {
	router.post("/devices/house", (req, res) => {
		res.status(200).json(house);
	});

	router.post("/devices/house/state", async (req, res) => {
		res.status(200).json({
			"bed-c-light1": 1,
		});
	});

	router.post("/devices/house/dashboard/:id/command", async (req, res) => {
		const id = req.params.id;
		const command = req.body.command;
		if (id == null || command == null) return res.status(400).json({"error": "missing parameters"});
		print("running command on dashboard " + id + ": " + command);
		controller.send({"id": id, "command": command});
		return res.status(200).json({"success": "command sent"});
	});
})();

// calendar
(() => {
	var calendarfile = Path.join(__dirname, 'calendar.json');

	(() => {
		try {
			fs.writeFileSync(calendarfile, "{}", { flag: 'wx' });
			print("calendar.file.create: success");
		} catch (e) {
			if (e.code === 'EEXIST') {
				print("calendar.file.create: exists");
			} else {
				warn("calendar.file.create: error: " + e);
			}
		}
	})();

	function getData() {
		try {
			return JSON.parse(fs.readFileSync(calendarfile, 'utf8'));
		} catch (e) {
			warn("calendar.file.get: error: " + e);
			return {"error": "internal server error"};
		}
	}

	function saveData(data) {
		try {
			fs.writeFileSync(calendarfile, JSON.stringify(data));
			return true;
		} catch (e) {
			warn("calendar.file.write: error: " + e);
			return false;
		}
	}

	function verifyStart(event, start, end, includeOngoing) {
		if (event.start.year > end.year) return false;
		if (event.start.month > end.month) return false;
		if (event.start.day > end.day) return false;

		if (!includeOngoing) {
			if (event.start.year < start.year) return false;
			if (event.start.month < start.month) return false;
			if (event.start.day < start.day) return false;
		}

		return true;
	}

	function verifyEnd(event, start, end) {
		if (event.end.year < start.year) return false;
		if (event.end.month < start.month) return false;
		if (event.end.day < start.day) return false;
		return true;
	}

	router.post("/calendar/get", (req, res) => {
		var events = getData()["events"];
		if (req.body.lists) events = events.filter(event => req.body.list.includes(event.list));
		const start = req.body.start;
		const end = req.body.end || req.body.start;

		if (start && end) {
			events = events.filter((event) => {
				var startResult = verifyStart(event, start, end, req.body.includeOngoing ?? true);
				var endResult = verifyEnd(event, start, end);
				return startResult || endResult;
			});
		}

		print("calendar.get: success");
		return res.status(200).json({"events": events});
	});

	router.post("/calendar/lists", (req, res) => {
		var events = getData()["events"];
		var lists  = [];

		events.forEach(obj => {
			if (obj.list && !lists.includes(obj.list)) {
				lists.push(obj.list);
			}
		});

		return res.status(200).json({"lists": lists});
	});

	router.post("/calendar/put", async (req, res) => {
		const range1 = req.body.range1;
		const range2 = req.body.range2 || req.body.range1;
		const data = getData();
		const name = req.body.name;
		const desc = req.body.description;
		const list = req.body.list;

		if (name == null || desc == null || range1 == null || range2 == null || range1.year == null || range1.month == null || range1.day == null || range2.year == null || range2.month == null || range2.day == null) {
			return res.status(400).json({"error": "fill out required fields"});
		}

		data["events"] ??= [];
		data["events"].push({
			start: {
				year: range1.year,
				month: range1.month,
				day: range1.day,
				hour: range1.hour,
				minute: range1.minute,
			},
			end: {
				year: range2.year,
				month: range2.month,
				day: range2.day,
				hour: range2.hour,
				minute: range2.minute,
			},
			name: name,
			description: desc,
			list: list ?? null,
		});

		data["events"].sort((a, b) => {
			var comparison = a.start.year - b.start.year;
			if (comparison !== 0) return comparison;

			comparison = a.start.month - b.start.month;
			if (comparison !== 0) return comparison;

			comparison = a.start.day - b.start.day;
			if (comparison !== 0) return comparison;

			comparison = a.start.hour - b.start.hour;
			if (comparison !== 0) return comparison;

			comparison = a.start.minute - b.start.minute;
			if (comparison !== 0) return comparison;
			return 0;
		});

		saveData(data);
		return res.status(200).json({"success": "set"});
	});
})();

function isInt(num) {
	return num !== null && Number.isInteger(num) && num >= 0 && num <= 100;
}

module.exports = router;