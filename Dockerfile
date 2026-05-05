# ═══════════════════════════════════════════════════════
# Multi-stage Dockerfile — Amazon JSP/Servlet App
# Stage 1 : Maven build  → produces .war file
# Stage 2 : Tomcat runtime → runs the .war
# ═══════════════════════════════════════════════════════

# ── Stage 1: Maven Build ────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-17-alpine AS builder

WORKDIR /build

COPY /pom.xml .
COPY /Amazon-Core/pom.xml Amazon-Core/pom.xml
COPY /Amazon-Web/pom.xml  Amazon-Web/pom.xml

RUN mvn dependency:go-offline -B -q

COPY /Amazon-Core/src Amazon-Core/src
COPY /Amazon-Web/src  Amazon-Web/src

RUN mvn clean package -DskipTests -B && \
    echo "=== Build Output ===" && \
    find . -name "*.war" | grep target

# ── Stage 2: Tomcat Runtime ─────────────────────────────
FROM tomcat:10.1-jre17-temurin-jammy AS runtime

RUN rm -rf /usr/local/tomcat/webapps/ROOT \
           /usr/local/tomcat/webapps/examples \
           /usr/local/tomcat/webapps/docs \
           /usr/local/tomcat/webapps/host-manager \
           /usr/local/tomcat/webapps/manager

COPY --from=builder /build/Amazon-Web/target/*.war \
     /usr/local/tomcat/webapps/ROOT.war

RUN groupadd -r tomcatgroup && \
    useradd -r -g tomcatgroup -d /usr/local/tomcat -s /bin/bash tomcatuser && \
    chown -R tomcatuser:tomcatgroup /usr/local/tomcat

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -fs http://localhost:8080/ || exit 1

USER tomcatuser

EXPOSE 8080

ENV JAVA_OPTS="-XX:+UseContainerSupport \
               -XX:MaxRAMPercentage=75.0 \
               -Djava.security.egd=file:/dev/./urandom \
               -Dfile.encoding=UTF-8"

CMD ["catalina.sh", "run"]
