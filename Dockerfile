FROM couchbase:community
COPY configure-couchbase.sh /opt/couchbase
HEALTHCHECK --interval=5s --timeout=1s CMD test "$( cat /tmp/status )" = "ready"
CMD ["/opt/couchbase/configure-couchbase.sh"]