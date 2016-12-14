{expect}       = require 'chai'
{Buffer}       = require 'buffer'
{EventEmitter} = require 'events'
sinon          = require 'sinon'
Client         = require '../src/Client'
ClientSocket   = require '../src/ClientSocket'

# Dummy ClientSocket implementation that just drops messages.
class DropSocket extends EventEmitter
    constructor: (options={}) ->
        if options.autoConnect ? true
            setTimeout (=> @doConnect()), 1

    doConnect: ->
        @emit 'connect'

    writeDataFrame: (data, done) ->
        @emit 'dropped', 1
        done new ClientSocket.DroppedError "Dropped message"

    unref: sinon.spy()

    close: ->

describe 'Client', ->
    it 'should group together dropped messages if they come together too quickly', (done) ->
        dropCount = 0

        client = new Client {}, {
            minTimeBetweenDropEvents: 10,
            _connect: -> return new DropSocket()
        }

        client.on 'disconnect', -> done new Error "Should not disconnect."

        client.on 'dropped', (count) ->
            try
                dropCount++

                if dropCount is 1
                    # Drop a single message for the first message
                    expect(count).to.equal 1
                if dropCount is 2
                    # But we should see the next two messages grouped into a single "dropped" event.
                    expect(count).to.equal 2
                    done()
            catch err
                done err

        client.writeDataFrame {line: 'foo'}
        client.writeDataFrame {line: 'foo'}
        client.writeDataFrame {line: 'foo'}

    it 'should call unref on the socket if options.unref is specified', (done) ->
        client = new Client {}, {
            minTimeBetweenDropEvents: 10,
            _connect: -> return new DropSocket()
            unref: true
        }
        client.on 'connect', ->
            setImmediate ->
                try
                    sinon.assert.calledOnce(client._socket.unref)
                catch err
                    return done err
                done()

    it 'should queue messages if the socket has disconnected', (done) ->
        client = new Client {}, {_connect: -> return new DropSocket(autoConnect: true)}

        client.on 'connect', ->
            client._disconnect()
            client.writeDataFrame {line: 'foo'}
            try
                expect(client.queueHighWatermark).to.equal 1
            catch err
                done err
            done()

    it 'should let you close the socket more than once (and do nothing on the second call)', ->
        client = new Client {}, {_connect: -> return new DropSocket()}

        client.close()
        client.close()
