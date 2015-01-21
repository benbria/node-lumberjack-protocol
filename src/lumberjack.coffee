# Methods for reading and writing [lumberjack](https://github.com/elasticsearch/logstash-forwarder/blob/master/PROTOCOL.md)
# protocol frames.

assert         = require 'assert'
{Buffer}       = require 'buffer'
{EventEmitter} = require 'events'
{Transform}    = require 'stream'
{FRAME_TYPE, VERSION, MAX_UINT_32} = require './constants'

TooShortError = (message) ->
    Error.captureStackTrace this, TooShortError
    @name = 'TooShortError'
    @message = message
TooShortError.prototype = Object.create(Error.prototype)

# Makes a frame that contains a single uint32 as the payload.
makeUint32Frame = (frameType, value) ->
    assert (value >= 0 and value <= MAX_UINT_32), "value must be a uint32."
    totalLength = 1 + 1 + 4 # version + frameType + 32 bit value
    b = new Buffer(totalLength)
    bOffset = 0

    bOffset += b.write "#{VERSION}#{frameType}"

    b.writeUInt32BE value, bOffset
    bOffset += 4

    # If this is off, we mis-calculated the totalLength.  This is bad.
    assert.equal bOffset, totalLength

    return b

# Makes a "window size" frame.
#
# * Sent from writer only.
# * `size` is the maximum number of unacknowledged data frames the writer will send before blocking
#   for acks.
#
# Returns a buffer.
#
exports.makeWindowSizeFrame = (size) -> makeUint32Frame FRAME_TYPE.WINDOW_SIZE, size

# Makes an "ack" frame.
#
# * Sent from reader only.
# * `sequence` is the sequence number to ack.  Bulk acks are supported. If the reader receives data
#   frames in sequence order 1,2,3,4,5,6, it can send an ack for '6' and the writer will take this
#   to mean that the reader is acknowledging all data frames before and including '6'.
#
# Returns a buffer.
#
exports.makeAckFrame = (sequence) -> makeUint32Frame FRAME_TYPE.ACK, sequence

# * `sequence` is the sequence number to use.
# * `data` is a hash of key, value pairs.
#
# Returns a Buffer.
#
exports.makeDataFrame = (sequence, data) ->
    version = '1'
    frameType = FRAME_TYPE.DATA

    dataLength = 0
    dataArray = Object.keys(data)
    # Remove any keys that are `null` or `undefined`
    .filter (key) -> data[key]?
    .map (key) ->
        # Convert to a string.
        # TODO: If an object, convert to JSON?
        value = "" + data[key]

        keyLength = Buffer.byteLength(key, 'utf8')
        valueLength = Buffer.byteLength(value, 'utf8')
        dataLength += 8 + keyLength + valueLength
        return {key, keyLength, value, valueLength}

    totalLength = 2 + # version + frameType
        8 + # sequence number + pair count
        dataLength

    # Build our buffer
    b = new Buffer(totalLength)
    bOffset = 0

    bOffset += b.write "#{version}#{frameType}"

    b.writeUInt32BE sequence, bOffset
    bOffset += 4

    b.writeUInt32BE dataArray.length, bOffset
    bOffset += 4

    dataArray.forEach (datum) ->
        b.writeUInt32BE datum.keyLength, bOffset
        bOffset += 4
        bOffset += b.write datum.key, bOffset

        b.writeUInt32BE datum.valueLength, bOffset
        bOffset += 4
        bOffset += b.write datum.value, bOffset

    # If this is off, we mis-calculated the totalLength.  This is bad.
    assert.equal bOffset, totalLength

    return b

DEFAULT_READ_BUFFER_SIZE = 4096

# Parses lumberjack messages.
#
# You feed data to LumberjackParser by repeatedly calling `write()`.  LumberjackParser will
# emit `data` events as frames are parse from the input, or alternatively you can fetch
# frames by calling `parser.read()`.
#
# At the moment, only support for ACK frames is included.
#
# Emits:
#
# * `error(err)` when an error occurs.
# * `data(frame)` when a new frame is received.  `data` will be a JSON object containing
#   defails of the message.
#   * For ACK frames, the returned object will be a `{type: 'ack', seq}` where `seq` is the
#     sequence number fo the most recently seen frame.
#
class exports.Parser extends Transform
    # TODO: Make this a full-blown writable object so we can just pipe to it.
    constructor: ->
        super
        @_writableState.objectMode = false;
        @_readableState.objectMode = true;
        @_buffer = new Buffer DEFAULT_READ_BUFFER_SIZE
        @_readBytes = 0

    _enlargeBuffer: ->
        newBuffer = new Buffer(@_buffer.length * 2)
        @_buffer.copy newBuffer
        @_buffer = newBuffer

    # Call when more data is available.  `buf` is a Buffer containing the new data.
    _transform: (chunk, encoding, done) ->
        while (@_readBytes + chunk.length) > @_buffer.length
            # We read more data from the socket than we can store in @_buffer - make the buffer
            # bigger.
            @_enlargeBuffer()

        # Write the data we received to the end of @_buffer
        chunk.copy @_buffer, @_readBytes
        @_readBytes += chunk.length

        try
            @_parse()
            done()
        catch err
            @emit 'error', err


    # Read messages from the buffer until we can't read them anymore.
    _parse: ->
        consumed = 0

        # We only read ack messages, and ack messages are always 6 bytes long
        while @_readBytes - consumed >= 6
            version = @_buffer.toString('UTF-8', consumed + 0, consumed + 1)
            assert version == '1', "Version should be 1, is #{version}"
            consumed += 1

            frameType = @_buffer.toString('UTF-8', consumed + 0, consumed + 1)
            frameTypeHex = @_buffer.toString('hex', consumed + 0, consumed + 1)
            consumed += 1

            switch frameType
                when FRAME_TYPE.ACK
                    seq = @_buffer.readUInt32BE(consumed)
                    @push {type: 'ack', seq}
                    consumed += 4
                else
                    throw new Error "Don't know how to parse frame of type '#{frameType}'' (#{frameTypeHex})"

        # Copy any unused bytes to the start of a new buffer
        oldBuffer = @_buffer
        @_buffer = new Buffer DEFAULT_READ_BUFFER_SIZE
        while (@_readBytes - consumed) > @_buffer.length
            @_enlargeBuffer
        oldBuffer.copy @_buffer, 0, consumed, @_readBytes
        @_readBytes -= consumed

