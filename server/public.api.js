const { print, warn, log, dotenv } = require('./localpkg.cjs');
const express = require('express');
const router = express.Router();

// Custom .env loader
dotenv();

function verify(req, res) {
    if (req.headers.auth == process.env.DASHBOARD_CODE) {
        print("public.verify: true");
    } else {
        print("public.verify: false (x3)");
        res.status(403).json({"code": "ATV x3"});
        return false;
    }
}

router.post("/weather", async (req, res) => {
    try {
        if (!verify(req, res)) return;
        const zip = req.body.zip || process.env.ZIP;
        print("global.weather: requesting for " + zip);
        const response = await fetch("https://api.weatherapi.com/v1/forecast.json?key=" + process.env.WEATHERAPI_KEY_PUBLIC + "&q=" + zip + "&days=3&aqi=no&alerts=no");

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

module.exports = router;