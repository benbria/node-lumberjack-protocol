To run these tests, you need a logstash server.  You can set one up with:

    docker run -it --rm -p 9997:9997 -v "$PWD"/logstash:/logstashcfg logstash -f /logstashcfg/logstash.conf

Then run individual tests and follow the instructions:

    node ./disconnectTest.js

If you need to regenerate the certificates for some reason:

    openssl req -x509 -newkey rsa:4096 -keyout logstash/key.pem -out logstash/cert.pem \
        -days 365 -nodes -subj "/C=CA/ST=Ontario/L=Ottawa/O=Logstash/CN=logstash.local"
