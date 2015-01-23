{expect}       = require 'chai'
{Buffer}       = require 'buffer'
{EventEmitter} = require 'events'
Client         = require '../src/Client'

# Dummy ClientSocket implementation that just drops messages.
class DropSocket extends EventEmitter
    constructor: ->
        setTimeout (=> @emit 'connect'), 1

    writeDataFrame: (data, done) ->
        @emit 'dropped', 1
        done()

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
