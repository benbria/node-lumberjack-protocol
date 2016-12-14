"use strict";

const lumberjack = require('..');
const fs = require('fs');

const connectionOptions = {
    host: "localhost",
    port: 9997,
    ca: [fs.readFileSync('./logstash/cert.pem', {encoding: 'utf-8'})],
    rejectUnauthorized: false
};

let state = 0;

let client = lumberjack.client(connectionOptions, {maxQueueSize: 500});

client.on("connect", () => {
    client.writeDataFrame({"line": "Connect!"});
    if(state === 0) {
        state++;
        console.log("Connect!  Please kill your logstash server.");
    } else if(state === 2) {
        console.log("Test passed!");
        process.exit(0);
    } else {
        console.log("Test failed - unexpected connect.")
        process.exit(1);
    }
});
client.on("disconnect", err => {
    if(state === 1) {
        state++;
        console.log("Disconnected.  Please restart your logstash server.");
    } else if(state === 2) {
        // We can get lots of disconnects while we're waiting for the logstash server to restart.
    } else {
        console.log("Test failed - unexpected disconnect.")
        process.exit(1);
    }
});
client.on("dropped", count => console.log(`Dropped ${count}`));
