What is it?
===========

This is a node.js implementation of the [lumberjack protocol](https://github.com/elasticsearch/logstash-forwarder/blob/master/PROTOCOL.md) from [logstash-forwarder](https://github.com/elasticsearch/logstash-forwarder).

At the moment, only the sender-side implementation is complete.  This is an excellent way to send
encrypted logs from your node.js app to your logstash instance.

Installation
============

    npm install --save node-logstash-forwarder

Usage
=====


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
