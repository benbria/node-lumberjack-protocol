assert           = require 'assert'
{EventEmitter}   = require 'events'
tls              = require 'tls'

lumberjack       = require './lumberjack'
{MAX_UINT_32}    = require './constants'

# TODO: Fix this
DEFAULT_WINDOW_SIZE = 2

# A simple logstash client.
#
# ClientSocket will automatically send a window size frame to the receiver on connect.
#
# ClientSocket will not send more than `windowSize` unacknowledged data frames to the receiever -
# additional frames are queued and will be sent when they can.  You can check the current size of
# the queue with `queueSize()`.
#
# If the queue gets larger than `maxQueueDepth`, then `dropFrames(queue)` will be called to
# shrink the size of the queue.  If `dropFrames()` doesn't shrink the queue sufficiently, or if
# it is not specified, then the oldest messages in the queue will be removed.
#
# Emits:
# * `connect` when the Client connects to the receiver.
# * `disconnect({err, lastSeq, lastAck, unackedCount})` when the client disconnects from the
#   receiver.  `err` will be the error which caused the disconnect, if there is one.  `lastSeq`
#   will be the last sequence number sent (or null if no messages have been sent.)  `lastAck` will
#   be the last squence number acknowledged by the receiver.  `unackedCount` is the number of
#   unacked messages that were lost.
# * `error(err)` if a parsing error occurs while reading data from the receiver.  The Client will
#   automatically try to reconnect.
# * `dropped(count)` if messages are dropped because the receiver is not acknowledging messages.
# * `ack(sequenceNumber)` when an acknowledge is received from the receiver.
#
# Properties:
# * `connected` - true if this ClientSocket is connected to the receiver, false otherwise.
# * `lastSequenceNumber` the sequence number of the last message sent to the receiver.
# * `lastAck` the sequence number of the most recent acknowledge from the receiver.
#
class ClientSocket extends EventEmitter
    # * `options.windowSize` is the maximum number of unacknowledged data frames the writer will
    #   send.
    #
    # * `options.maxQueueDepth` is the maximum number of frames to queue past the `windowSize`.
    #   If this option is 0, then if we exceed the window size, messages will be dropped
    #   immediately.  Note that the queue is also used to queue messages which are sent before
    #   this ClientSocket connects.  Default is the window size.
    # * `options.dropFrames(queue)` will be called to discard messages from the queue.  `dropFrames`
    #   is passed in an array of `{data, seq}` objects, and should return a new array with all the
    #   unimportant frames removed.  This function will be called every time the queue gets too
    #   large - if it only removes a single data frame from the queue, then it will be called
    #   on every message.
    #
    constructor: (@options={}) ->
        @connected = false

        @_windowSize = @options.windowSize ? DEFAULT_WINDOW_SIZE
        @_maxQueueDepth = @options.maxQueueDepth ? @_windowSize

        @_nextSequenceNumber = 1
        @lastAck = 0

        @_queue = []
        @_queueHighwaterMark = 0

        # Create a new parser to process data.
        @_parser = new lumberjack.Parser()
        @_parser.on 'data', @_onData
        @_parser.on 'error', (err) =>
            console.log "Parser error"
            @emit 'error', err
            @_disconnect err

    connect: (tlsConnectOptions) ->
        if tlsConnectOptions.socket?
            @_socket = tlsConnectOptions.socket
        else
            @_socket = tls.connect tlsConnectOptions

        @_socket.on 'secureConnect', =>
            @_socket.write lumberjack.makeWindowSizeFrame(@_windowSize), null, =>
                @connected = true
                @_flushQueue()
                @emit 'connect'

        @_socket.on 'error', @_disconnect

        @_socket.on 'end', => @_disconnect(null)

        @_socket.on 'data', (data) => @_parser.write data

    _disconnect: (err) =>
        console.log "boom"
        unackedCount = if @lastSequenceNumber >= @lastAck
            @lastSequenceNumber - @lastAck
        else
            @lastSequenceNumber - (@lastAck - MAX_UINT_32) + 1

        if @connected then @emit 'disconnect', {
            err,
            lastSeq: @lastSequenceNumber
            lastAck: @lastAck
            unackedCount
        }
        @connected = false

        @_socket?.removeAllListeners()
        @_socket = null

        # Since we're not going to send any more events...
        @removeAllListeners()

    _onData: (data) =>
        assert data.type == 'ack', "Receiver should only ever send 'ack' messages: #{data.type}"
        @lastAck = data.seq
        @emit 'ack', data.seq
        @_flushQueue()

    _canSend: (sequenceNumber) ->
        # The lumberjack protocol says we should block if we've sent `@_windowsize` unacknowledged
        # messages.
        @connected and (sequenceNumber - @lastAck <= @_windowSize)

    _getSequenceNumber: ->
        console.log @_nextSequenceNumber
        @lastSequenceNumber = @_nextSequenceNumber++
        if @_nextSequenceNumber > MAX_UINT_32 then @_nextSequenceNumber = 0
        return @lastSequenceNumber

    # `data` here should be a `{file, host, line, offset}` object, where:
    #
    # * `line` is the line from the log file.  This field is mandatory if the receiver is logstash.
    # * `host` (optional) is the hostname of the host that generated the line.
    # * `file` (optional) is the name of the log file.
    # * `offset` (optional) an integer - the offset of the line in the log file.
    #
    # Additional field in `data` will be passed up to logstash.  Logstash will add these to the log
    # entry.
    #
    writeDataFrame: (data) ->
        sequenceNumber = @_getSequenceNumber()
        if @_queue.length is 0 and @_canSend(sequenceNumber)
            # Send the message right away.
            console.log "Sending #{sequenceNumber}"
            @_socket.write lumberjack.makeDataFrame(sequenceNumber, data)

        else if @_maxQueueDepth > 0
            # Queue the message.  Note if there are too many messages in the queue, this will be
            # dealt with below in `_flushQueue()`.

            console.log "Queueing #{sequenceNumber} - #{@connected} - #{sequenceNumber - @lastAck}"
            # FIXME: If we drop messages from the queue, then the sequence numbers are going to
            # be all out of whack.
            @_queue.push {
                seq: sequenceNumber
                data
            }

            # Send as much as we can from the queue
            @_flushQueue()

        else
            # TODO: Rate limit dropped events.
            @emit 'dropped', 1


    _flushQueue: ->
        @_queueHighwaterMark = Math.max(@_queueHighwaterMark, @_queue.length)

        # TODO: Use compressed frames?
        # Write data from the queue until we've hit the window size.
        if @_queue.length > 0 then console.log "Can we send #{@_queue[0].seq}"
        console.log @_queue
        while @_queue.length > 0 and @_canSend(@_queue[0].seq)
            {seq, data} = @_queue.shift()
            console.log "Sending #{seq} from queue"
            @_socket.write lumberjack.makeDataFrame(seq, data)

        # If the queue is too big, drop messages as required.
        if @_queue.length > @_maxQueueDepth
            oldCount = @_queue.length
            if @options.dropFrames?
                @_queue = @options.dropFrames @_queue
            @_queue.shift() while @_queue.length > @_maxQueueDepth

            console.log "Dropping #{oldCount - @_queue.length}"
            @emit 'dropped', oldCount - @_queue.length


    queueSize: -> return @_queue.length

    queueHighwaterMark: -> return @_queueHighwaterMark

    getLastSequenceNumber: -> return @_nextSequenceNumber - 1

    close: ->
        @_disconnect()

module.exports = ClientSocket