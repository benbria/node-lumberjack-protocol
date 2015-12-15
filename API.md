Client
------

A `Client` object connects to the reciever and sends messages.  The Client will
automatically reconnect if the connection fails.  Any messages sent while the Client is disconnected
will be queued and sent when the connection is re-established.

## lumberjack.client(tlsConnectOptions, clientOptions={})

Creates a Client.

`tlsConnectOptions` is passed directly to
[`tls.connect()`](http://nodejs.org/api/tls.html#tls_tls_connect_options_callback) to create the
TLS connection to the receiver (the logstash server.)  At a minimum, you should set `host` and `port`.

`clientOptions` consists of:

* `windowSize` - the windowSize to send to the receiver (see
  [caveats](https://github.com/benbria/node-lumberjack-protocol#caveats) section
  for a discussion about how `lumberjack-protocol` treats the `windowSize`.)  Defaults to 1000.

* `maxQueueSize` - the maximum number of messages to queue while disconnected.
  If this limit is hit, all messages in the queue will be filtered with
  `allowDrop(data)`.  Only messages which this function returns true for will be
  removed from the queue.  If there are still too many messages in the queue at this point
  the the oldest messages will be dropped.  Defaults to 500.

* `allowDrop(data)` - this will be called when deciding which messages to drop.
  By dropping lower priority messages (info and debug level messages, for example) you can
  increase the chances of higher priority messages getting through when the Client is
  having connection issues, or if the receiver goes down for a short period of time.
  This function is used both to drop messages from the queue while disconnected, and to drop
  messages if the receiver is taking too long to acknowledge messages.

  Note that this function will be called on all messages in the queue every time the queue grows
  too large - if this function does not return true for any messages, then it could be called
  for every message in the queue every time a message is queued.

* `options.reconnect` - time, in ms, to wait between reconnect attempts.  Defaults to 3 seconds.

* `options.unref` - if true, will call [unref](https://nodejs.org/api/net.html#net_socket_unref) on the underlying
  socket.  This will allow the program to exit if this is the only active socket in the event system.

## Events

Client inherits from [EventEmitter](http://nodejs.org/api/events.html#events_class_events_eventemitter), and emits the following:

* `connect` when the Client connects to the receiver.

* `disconnect(err)` when the client disconnects from the receiver, or when the client fails to
  connect to the receiver.  `err` will be the error which caused the disconnect, if there is one.
  The Client will automatically reconnect.

* `dropped(count)` if messages are dropped because the receiver is not acknowledging messages
  fast enough, or because the Client is unable to connect to the receiver and the Client's queue
  is full.

## Methods

### Client.writeDataFrame(data)

`data` here should be a `{file, host, line, offset}` object, where:

* `host` - the hostname of the host that generated the line.  Defaults to os.hostname().
* `line` - the line from the log file.  If you are sending to a logstash receiver, this field
  is mandatory - logstash will freak out if `line` is missing.
* `file` (optional) - the name of the log file.
* `offset` (optional) an integer - the offset of the line in the log file.

Additional field in `data` will be passed up to the receiver.  If you are sending to Logstash,
it will add these to the log entry.

### Client.close()

Cleanly shut down a Client and prevent it from reconnecting.  If there are queued messages, they
will be lost.

### Client.queueHighWatermark

A readable property which returns the largest size the queue has ever been.
