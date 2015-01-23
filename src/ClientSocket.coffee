assert           = require 'assert'
{EventEmitter}   = require 'events'
tls              = require 'tls'

lumberjack       = require './lumberjack'
{MAX_UINT_32}    = require './constants'

DEFAULT_WINDOW_SIZE = 1000
SEND_WINDOW_SIZE_FACTOR = 10

DroppedError = (message) ->
    Error.captureStackTrace this, TooShortError
    @name = 'DroppedError'
    @message = message
DroppedError.prototype = Object.create(Error.prototype)


# A simple lumberjack client.
#
# ClientSocket will automatically send a window size frame to the receiver on connect.
#
# Emits:
# * `connect` when the Client connects to the receiver.
#
# * `error(err)` if an error occurs.
#
# * `dropped(count)` if messages are dropped because the receiver is not acknowledging messages
#   fast enough.
#
# * `ack(sequenceNumber)` when an acknowledge is received from the receiver.
#
# Properties:
# * `connected` - true if this ClientSocket is connected to the receiver, false otherwise.
# * `lastSequenceNumber` the sequence number of the last message sent to the receiver.
# * `lastAck` the sequence number of the most recent acknowledge from the receiver.
#
class ClientSocket extends EventEmitter
    DroppedError: DroppedError

    # * `options.windowSize` the windowSize to send to the receiver.
    # * `options.allowDrop(data)` called before a message is dropped - if this returns false,
    #   then the message will be sent to the receiver even though it should be dropped.  Use this
    #   carefully as this has the potential to overwhelm the receiver.
    constructor: (@options={}) ->
        @connected = false
        @_closed = false

        @_windowSize = @options.windowSize ? DEFAULT_WINDOW_SIZE

        @_nextSequenceNumber = 1
        @lastAck = 0

        # Create a new parser to process data.
        @_parser = new lumberjack.Parser()
        @_parser.on 'data', @_onData
        @_parser.on 'error', @_disconnect

    # `tlsConnectOptions` are options used to connect to the receiver.  Any options which can be
    # passed to `tls.connect()` can be passed here.
    connect: (tlsConnectOptions) ->
        @_socket = tls.connect tlsConnectOptions

        @_socket.on 'secureConnect', =>
            @_socket.write lumberjack.makeWindowSizeFrame(@_windowSize), null, =>
                @connected = true
                @emit 'connect'

        @_socket.on 'error', @_disconnect

        @_socket.on 'end', => @_disconnect()

        @_socket.pipe @_parser

    _disconnect: (err) =>
        if err
            @emit 'error', err
        else
            @emit 'end'

        @connected = false

        @_socket?.removeAllListeners()
        @_socket = null

        # Since we're not going to send any more events...
        @removeAllListeners()

    # Handle acks from the parser.
    _onData: (data) =>
        assert data.type == 'ack', "Receiver should only ever send 'ack' messages: #{data.type}"
        @lastAck = data.seq
        @emit 'ack', data.seq

    # Return the next unused sequence number
    _getSequenceNumber: ->
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
    # Additional field in `data` will be passed up to the receiver.  If the receiver is Logstash,
    # it will add these to the log entry.
    #
    # `done` is an optional callback.
    #
    writeDataFrame: (data, done) ->
        if !@connected then done new Error "Can't write data when not connected."

        drop = ( (@_nextSequenceNumber - @lastAck) > (@_windowSize * SEND_WINDOW_SIZE_FACTOR) ) and
                (!@options.allowDrop? or !!@options.allowDrop(data))
        if drop
            @emit 'dropped', 1
            done new DroppedError "Dropped message"
        else
            @_socket.write lumberjack.makeDataFrame(@_getSequenceNumber(), data), null, done

    getLastSequenceNumber: -> return @_nextSequenceNumber - 1

    close: ->
        @_closed = true
        @_disconnect()

module.exports = ClientSocket