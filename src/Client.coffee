assert           = require 'assert'
{EventEmitter}   = require 'events'

ClientSocket     = require './ClientSocket'

DEFAULT_QUEUE_SIZE = 500
DEFAULT_RECONNECT_TIME_IN_MS = 3000
MIN_TIME_BETWEEN_DROPPED_EVENTS_IN_MS = 1000

# Connects to a lumberjack receiver and sends messages.
#
# `Client` connects to the lumberjack receiver in the background and will automatically reconnect
# if the connection is lost.  Messages sent to the `Client` while disconnected will be queued
# and sent automatically once the connection is re-established.
#
# Emits:
# * `connect` when the Client connects to the receiver.
#
# * `disconnect(err)` when the client disconnects from the receiver, or when the client fails to
#   connect to the receiver.  `err` will be the error which caused the disconnect, if there is one.
#   The Client will automatically reconnect.
#
# * `dropped(count)` if messages are dropped because the receiver is not acknowledging messages
#   fast enough.
#
class Client extends EventEmitter

    # * `tlsConnectOptions` are options used to connect to the receiver.  Any options which can be
    #   passed to `tls.connect()` can be passed here.
    #
    # * `options.windowSize` - passed on to the ClientSocket.
    #
    # * `options.maxQueueSize` - the maximum number of messages to queue while disconnected.
    #   If this limit is hit, all messages in the queue will be filtered with
    #   `options.allowDrop(data)`.  Only messages which this function returns true for will be
    #   removed from the queue.  If there are still too many messages in the queue at this point
    #   the the oldest messages will be dropped.  Defaults to 500.
    #
    # * `options.allowDrop(data)` - this will be called when deciding which messages to drop.
    #   By dropping lower priority messages (info and debug level messages, for example) you can
    #   increase the chances of higher priority messages getting through when the Client is
    #   having connection issues, or if the receiver goes down for a short period of time.
    #
    # * `options.reconnect` - time, in ms, to wait between reconnect attempts.  Defaults to 3
    #   seconds.
    #
    # * `options.unref` - if true, will call [unref](https://nodejs.org/api/net.html#net_socket_unref) on the
    #   underlying socket.  This will allow the program to exit if this is the only active socket in the event system.
    #
    constructor: (@tlsConnectOptions, @options={}) ->
        @connected = false
        @_closed = false

        @_hostname = require('os').hostname()

        @_queue = []
        @_maxQueueSize = @options.maxQueueSize ? DEFAULT_QUEUE_SIZE
        @_reconnectTime = @options.reconnect ? DEFAULT_RECONNECT_TIME_IN_MS
        @_minTimeBetweenDropEvents = @options.minTimeBetweenDropEvents ? MIN_TIME_BETWEEN_DROPPED_EVENTS_IN_MS

        @_connect()

        @_lastDropEventTime = null
        @_dropTimer = null
        @_dropCount = 0

        @queueHighWatermark = 0

    # `data` here should be a `{file, host, line, offset}` object, where:
    #
    # * `host` - the hostname of the host that generated the line.  Defaults to os.hostname().
    # * `line` - the line from the log file.  If you are sending to a logstash receiver, this field
    #   is mandatory - logstash will freak out if `line` is missing.
    # * `file` (optional) - the name of the log file.
    # * `offset` (optional) an integer - the offset of the line in the log file.
    #
    # Additional field in `data` will be passed up to the receiver.  If you are sending to Logstash,
    # it will add these to the log entry.
    #
    writeDataFrame: (data) ->
        throw new Error "Client is closed" if @_closed

        # This is modeled after https://github.com/elasticsearch/logstash-forwarder/blob/master/publisher1.go
        # `writeDataFrame()`.
        #
        if !@connected or !@_socket
            # Queue this for later
            @_queueMessage data

        else
            if !data.host?
                # Clone `data`
                record = {}
                record[key] = value for key, value of data

                record.host = @_hostname
                data = record

            @_socket.writeDataFrame data, (err) =>
                if err? and !(err instanceof ClientSocket.DroppedError)
                    # Couldn't send the message - queue for later.
                    @_queueMessage data

    # Shut down this client.
    close: ->
        @_closed = true
        @_disconnect()

    _connect: ->
        return if @_closed

        # Handy hook for unit testing.
        if @options._connect?
            @_socket = @options._connect this, @tlsConnectOptions

        else
            @_socket = new ClientSocket @options
            @_socket.connect @tlsConnectOptions

        @_socket.on 'connect', =>
            @connected = true
            @emit 'connect'
            @_sendQueuedMessages()
            if @options.unref then @_socket.unref()

        @_socket.on 'end', @_disconnect

        @_socket.on 'error', @_disconnect

        @_socket.on 'dropped', (count) => @_dropped count

    _disconnect: (err) =>
        @emit 'disconnect', err
        @connected = false

        if @_socket?
            @_socket.close()
            @_socket?.removeAllListeners()
            @_socket = null

        if !@_closed and !@_connectTimer?
            @_connectTimer = setTimeout (
                =>
                  @_connectTimer = null
                  @_connect()
                ), @_reconnectTime

    _queueMessage: (data) ->
        @_queue.push data

        @queueHighWatermark = Math.max @_queue.length, @queueHighWatermark

        # If the queue is too big, shrink it.
        if @_queue.length >= @_maxQueueSize
            originalQueueSize = @_queue.length
            if @options.allowDrop?
                @_queue = @_queue.filter @options.allowDrop

            # If the queue is still too big, remove items from the head of the queue.
            @_queue.shift() while @_queue.length >= @_maxQueueSize

            @_dropped originalQueueSize - @_queue.length

    _sendQueuedMessages: ->
        return if @_queue.length is 0 or !@_socket?

        message = @_queue.shift()
        @_socket.writeDataFrame message, (err) =>
            if err? and !(err instanceof ClientSocket.DroppedError)
                # Put this back at the start of the queue and we'll try later.
                @_queue.unshift message
            else
                # Send some more messages.
                setImmediate => @_sendQueuedMessages()

    _dropped: (count) ->
        @_dropCount += count

        # If there's already a timer running, wait for the timer to send anything.
        if @_dropTimer?
            return

        sendDropEvent = =>
            @emit 'dropped', @_dropCount
            @_dropCount = 0
            @_dropTimer = null
            @_lastDropEventTime = Date.now()

        if !@_lastDropEventTime? or @_lastDropEventTime + @_minTimeBetweenDropEvents < Date.now()
            sendDropEvent()
        else
            @_dropTimer = setTimeout(sendDropEvent, @_minTimeBetweenDropEvents)

module.exports = Client
