FROM openjdk:11-jdk-slim
VOLUME /tmp
ARG JAR_FILE
ENV TZ America/El_Salvador
COPY ${JAR_FILE} app.jar
COPY docker/entrypoint.sh entrypoint.sh
RUN ["chmod", "+x", "entrypoint.sh"]

ENTRYPOINT ["./entrypoint.sh"]
