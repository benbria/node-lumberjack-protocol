Client = require './Client'

# `tlsConnectOptions` are options used to connect to the lumberjack receiver.
#
# * `options.windowSize` is the maximum number of unacknowledged data frames the writer will
#   send before "blocking" for acks.
#
exports.client = (tlsConnectOptions, clientOptions={}) ->
    return new Client tlsConnectOptions, clientOptions
