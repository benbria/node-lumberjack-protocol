[![NPM](https://nodei.co/npm/lumberjack-protocol.png?downloads=true&downloadRank=true&stars=true)](https://nodei.co/npm/lumberjack-protocol/)

[![Build Status](https://travis-ci.org/benbria/node-lumberjack-protocol.svg?branch=master)](https://travis-ci.org/benbria/node-lumberjack-protocol)
[![Coverage Status](https://coveralls.io/repos/benbria/node-lumberjack-protocol/badge.svg)](https://coveralls.io/r/benbria/node-lumberjack-protocol)
[![Dependency Status](https://david-dm.org/benbria/node-lumberjack-protocol.svg)](https://david-dm.org/benbria/node-lumberjack-protocol)
[![devDependency Status](https://david-dm.org/benbria/node-lumberjack-protocol/dev-status.svg)](https://david-dm.org/benbria/node-lumberjack-protocol#info=devDependencies)

What is it?
===========

This is a node.js implementation of the [lumberjack protocol](https://github.com/elasticsearch/logstash-forwarder/blob/master/PROTOCOL.md) from [logstash-forwarder](https://github.com/elasticsearch/logstash-forwarder).

At the moment, only the sender-side implementation is complete.  This is an excellent way to send
encrypted logs from your node.js app to your logstash instance.  If you are using [bunyan](https://github.com/trentm/node-bunyan), be sure to check out [bunyan-lumberjack](https://github.com/benbria/node-bunyan-lumberjack).

Contents
--------

* [Installation](#installation)
* [Usage](#usage)
* [API](https://github.com/benbria/node-lumberjack-protocol/blob/master/API.md)
* [Caveats](#caveats)
* [Troubleshooting](#troubleshooting)


Installation
============

    npm install --save lumberjack-protocol

Usage
=====

Create a lumberjack `Client`; it will connect to the server in the background, automatically
reconnect, and queue any messages that you try to send while disconnected:

    var lumberjack = require('lumberjack-protocol');
    var fs = require('fs');

    var connectionOptions = {
        host: "myserver.com",
        port: 5000,
        ca: [fs.readFileSync('./logstash.crt', {encoding: 'utf-8'})]
    };

    var client = lumberjack.client(connectionOptions, {maxQueueSize: 500});

    client.writeDataFrame({"line": "Hello World!"});

API
===

Full API documentation can be found [here](https://github.com/benbria/node-lumberjack-protocol/blob/master/API.md).

Caveats
=======

According to the [lumberjack specification](https://github.com/elasticsearch/logstash-forwarder/blob/master/PROTOCOL.md#window-size-frame-type),
the window size is "maximum number of unacknowledged data frames the writer will send
before blocking for acks."  Node.js doesn't support blocking IO; you might think it would
be reasonable to drop messages if the client runs into the window size, but in actual fact
the current logstash implementation will only send an ack every `windowSize`th data frame.
In other words, if `windowSize` is 10, then logstash will only send an ack every 10th data
frame, so when sending to logstash we would very often lose frames right after the 10th frame
while waiting (which would be less than ideal.)

An alternative here would be to queue messages while we wait for the ack, and
then send all the queued messages in a burst.  This introduces a great deal of complexity,
however, as we have to deal with queue management.  It does offer some advantages in that
we can be selective in how we drop messages (if the queue gets full, for example, we can purge all
the debug and info level events from the queue when it comes time to drop messages, for example,
meaning that the error messages will have a higher likelihood of getting through.)

The approach taken here is less nuaced - we'll send up to ten times the `windowSize` to the
receiver before waiting for an ack.  If we don't get an ack, we'll start dropping messages.
You can specify a `allowDrop(data)` function that will prevent messages from being dropped if
there are certain types of messages you want to ensure get through (errors, for example.)

Troubleshooting
===============

### Hostname/IP doesn't match certificate's altnames

* If you are connecting to a server using a hostname, the hostname must match either the subject's
  CN in the certificate, or one of the certificate's subjectAltNames.
* If you are connecting with an IP address, the IP address must be listed in the certificate's
  subjectAltNames.  Note that node.js will not check to see if the IP matches the subject CN.
* If you are using node >=0.11.x, you can use checkServerIdentity:

        var lj = lumberjack.client({
            checkServerIdentity: function (host, cert) {
                return cert.subject.cn == "expectedservername.com";
            },
            ...
        });

* If you're doing testing, you can do this the very insecure way, but note this is **not secure**:

        var lj = lumberjack.client({
            rejectUnauthorized: false,
            ...
        });
        
  You may also see suggestions to set an enviroment variable:
  
      process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";
      
  which is effectively the same thing.  Both of these options will bypass certificate checks which
  will make it easy for a third party to intercept your traffic using a man-in-the-middle attack.
  Do not set these options unless you are very sure you know what you are doing.

### Error: self signed certificate, code: DEPTH_ZERO_SELF_SIGNED_CERT

If you're using a self-signed certificate, be sure you are passing it in the `ca` parameter to
the `connectOptions`.  You can fetch the certificate your server is using with openssl:

    openssl s_client -showcerts -connect myserver.com:5000 -tls1
