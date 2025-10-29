FROM docker.elastic.co/logstash/logstash:8.14.1

# Install required plugins
RUN logstash-plugin install logstash-input-http logstash-output-http logstash-filter-mutate

# Copy entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 80

# Run as root to bind to privileged port 80
USER root

ENTRYPOINT ["bash", "/usr/local/bin/entrypoint.sh"]


