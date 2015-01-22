{expect} = require 'chai'
{Buffer} = require 'buffer'
lumberjack = require '../src/lumberjack'

frameToArray = (frame) ->
    answer = frame.toJSON()

    # node 0.10.x just gives us an array.

    # node 0.11.x gives us back a `{type, data}` object.
    if answer.data?
        answer = answer.data
    return answer

describe 'lumberjack protocol', ->
    it 'should generate an ACK frame', ->
        frame = lumberjack.makeAckFrame(4)
        expect(frameToArray frame).to.eql [0x31, 0x41, 0x00, 0x00, 0x00, 0x04]

    it 'should generate a window size frame', ->
        frame = lumberjack.makeWindowSizeFrame(5000)
        expect(frameToArray frame).to.eql [0x31, 0x57, 0x00, 0x00, 0x13, 0x88]

    it 'should generate a data frame', ->
        frame = lumberjack.makeDataFrame 10, {line: "hello"}
        expect(frameToArray frame).to.eql [
            0x31, # version = '1'
            0x44, # frameType = 'D'
            0x00, 0x00, 0x00, 0x0A, # sequence number
            0x00, 0x00, 0x00, 0x01, # number of pairs
            0x00, 0x00, 0x00, 0x04, # length of 'line'
            0x6C, 0x69, 0x6E, 0x65, # 'line'
            0x00, 0x00, 0x00, 0x05, # length of 'hello'
            0x68, 0x65, 0x6c, 0x6c, 0x6f # 'hello'
        ]

    describe 'Parser', ->
        it 'should parse an ACK frame', ->
            parser = new lumberjack.Parser()
            parser.write lumberjack.makeAckFrame(4)

            data = parser.read()
            expect(data.type).to.equal 'ack'
            expect(data.seq).to.equal 4

        it 'should parse two ACK frames split across two buffers', ->
            ack1 = lumberjack.makeAckFrame(4)
            ack2 = lumberjack.makeAckFrame(8)

            # Split our acks across two buffers.
            a = new Buffer(8)
            b = new Buffer(4)
            ack1.copy a
            ack2.copy a, 6, 0, 2
            ack2.copy b, 0, 2, 6

            parser = new lumberjack.Parser()

            parser.write a

            data = parser.read()
            expect(data.type).to.equal 'ack'
            expect(data.seq).to.equal 4

            # Should not be able to read another frame since the parser only has half the next frame
            expect(parser.read()).to.equal null

            parser.write b
            data = parser.read()
            expect(data.type).to.equal 'ack'
            expect(data.seq).to.equal 8
