const fs = require('fs');
const path = require('path');
const https = require('https');
const { spawn } = require('child_process');
const { print, warn, debug, getData, saveData, moveToTop } = require('../localpkg.cjs');

async function handle(req, res) {
    try {
        const {message} = req.body;
        print("announce message: " + message);
    
        if (message == undefined || message == null) {
            return res.status(400).json({"error": "invalid message", "message": message});
        }

        await announce(message, req.body.locale ?? 'en-US');
        res.status(200).json({"success": "message sent", "message": message});
    } catch (e) {
        warn("announce.handle error: " + e);
        res.status(500).json({"error": "internal server error"});
    }
}

async function announce(message, language) {
    try {
        const mp3 = path.join(path.resolve(path.resolve(__dirname, '..'), '..'), 'temp', 'announce.mp3');
        const url = "https://translate.google.com/translate_tts?ie=UTF-8&tl=" + language + "&client=tw-ob&q=" + encodeURIComponent(message);
        print("announce: fetching audio from url: " + url);

        https.get(url, (response) => {
            try {
                if (response.statusCode === 200) {
                    print('saving file: ' + mp3);
                    const file = fs.createWriteStream(mp3);
                    response.pipe(file);
                    
                    file.on('finish', () => {
                        try {
                            const root = "ffplay";
                            const args = ["-autoexit", "-nodisp", mp3];
                            const command = root + " " + args.join(' ');
                            const config = getData();

                            print("announce: starting player.play for path: " + mp3 + " and command: " + command);
                            const process = spawn(root, args, {
                                stdio: "inherit",
                                shell: true, 
                            });

                            if (!config.announcedmessages.some(item => item.message === message)) {
                                config.announcedmessages.unshift({ message, date: new Date().toISOString() });
                            } else {
                                config.announcedmessages = moveToTop(config.announcedmessages, "message", message);
                                const item = config.announcedmessages.find(item => item.message === message);
                                if (item) {
                                    item.date = new Date().toISOString();
                                }
                            }                

                            saveData(config);
                            process.on("close", (code) => {
                                print(`process exited with code ${code}`);
                                if (debug) {
                                    print("announce: recording available at " + mp3);
                                } else {
                                    fs.unlinkSync(mp3);
                                    print("announce: deleted file " + mp3);
                                }
                            });
                        } catch (e) {
                            warn("announce (3): " + e);
                        }
                    });
                } else {
                    throw new Error('download translater failed: ' + response.statusCode);
                }
            } catch (e) {
                warn("announce (2): " + e);
            }
        }).on('error', (e) => {
            warn('announce (1): ' + e);
        });
    } catch (e) {
        warn("announce (0): " + e);
    }
}

module.exports = {
    handle,
};
