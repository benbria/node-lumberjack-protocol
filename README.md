What is it?
===========

This is a node.js implementation of the [lumberjack protocol](https://github.com/elasticsearch/logstash-forwarder/blob/master/PROTOCOL.md) from [logstash-forwarder](https://github.com/elasticsearch/logstash-forwarder).

At the moment, only the sender-side implementation is complete.  This is an excellent way to send
encrypted logs from your node.js app to your logstash instance.

Contents
--------

* [Installation](#installation)
* [Usage](#usage)
* [API](https://github.com/benbria/node-lumberjack-protocol/blob/master/API.md)
# [Caveats](#caveats)
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
        host: "192.168.10.11",
        port: 9997,
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

The most common reason you're not going to be able to connect is because node.js throws an
Error that says "Hostname/IP doesn't match certificate's altnames".

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

* If you're especially lazy, you can do this the very insecure way, but note this is not advisable
  for a production system:

        var lj = lumberjack.client({
            rejectUnauthorized: false,
            ...
        });

