{expect}       = require 'chai'
{Buffer}       = require 'buffer'
{EventEmitter} = require 'events'
sinon          = require 'sinon'
Client         = require '../src/Client'

# Dummy ClientSocket implementation that just drops messages.
class DropSocket extends EventEmitter
    constructor: ->
        setTimeout (=> @emit 'connect'), 1

    writeDataFrame: (data, done) ->
        @emit 'dropped', 1
        done()

    unref: sinon.spy()

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
                    expect(count).to.equal 1
                if dropCount is 2
                    expect(count).to.equal 2
                    done()
            catch err
                done err

        client.writeDataFrame {line: 'foo'}
        client.writeDataFrame {line: 'foo'}
        client.writeDataFrame {line: 'foo'}

    it 'should call unref on the socket if options.unref is specified', ->
        client = new Client {}, {
            minTimeBetweenDropEvents: 10,
            _connect: -> return new DropSocket()
            unref: true
        }

        sinon.assert.calledOnce(client._socket.unref)
