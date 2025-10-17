# Stage 1: Build application
FROM eclipse-temurin:21-jdk-alpine AS builder

# Set working directory
WORKDIR /build

# Set environment variables for Maven Wrapper
ARG MVNW_REPOURL=https://repo.maven.apache.org/maven2
ARG MVNW_USERNAME
ARG MVNW_PASSWORD
ARG MVNW_VERBOSE

# Set up Maven mirror repository (Use the same config of Maven Wrapper)
RUN --mount=type=cache,target=/root/.m2 \
    echo '<?xml version="1.0" encoding="UTF-8"?> \
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0" \
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" \
         xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 \
         http://maven.apache.org/xsd/settings-1.0.0.xsd"> \
    <servers> \
        <server> \
            <id>mirror</id> \
            <username>'${MVNW_USERNAME}'</username> \
            <password>'${MVNW_PASSWORD}'</password> \
        </server> \
    </servers> \
    <mirrors> \
        <mirror> \
            <id>mirror</id> \
            <mirrorOf>*</mirrorOf> \
            <url>'${MVNW_REPOURL}'</url> \
        </mirror> \
    </mirrors> \
</settings>' > /root/.m2/settings.xml

# Copy only the files needed for dependency resolution first
COPY .mvn/ .mvn/
COPY --chmod=544 mvnw ./
COPY pom.xml ./

# Download dependencies with caching
RUN --mount=type=cache,target=/root/.m2 ./mvnw dependency:go-offline -B

# Copy source code
COPY src src

# Build application jar with caching
RUN --mount=type=cache,target=/root/.m2 ./mvnw package -DskipTests -B

# Extract layers for better caching
RUN java -Djarmode=layertools -jar target/*.jar extract --destination extracted

# Stage 2: Create runtime image
FROM eclipse-temurin:21-jre-alpine

# Set working directory
WORKDIR /app

# Install required packages
RUN apk add --no-cache curl

# Create non-root user
RUN addgroup -g 1000 spring && adduser -u 1000 -G spring -s /bin/sh -D spring

# Copy layers from builder stage
COPY --from=builder --chown=spring:spring /build/extracted/dependencies/ ./
COPY --from=builder --chown=spring:spring /build/extracted/snapshot-dependencies/ ./
COPY --from=builder --chown=spring:spring /build/extracted/spring-boot-loader/ ./
COPY --from=builder --chown=spring:spring /build/extracted/application/ ./

# Set environment variables
ENV TZ=Asia/Shanghai \
    SPRING_PROFILES_ACTIVE=prod \
    MAIN_CLASS=com.example.demo.DemoApplication \
    JAVA_OPTS=""

# Set HEALTHCHECK
HEALTHCHECK --start-period=20s --interval=10s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

# Switch to non-root user
USER spring:spring

# Expose application port
EXPOSE 8080

# Set the entrypoint with proper Java options
ENTRYPOINT ["sh", "-c", "exec java \
    -cp BOOT-INF/classes:BOOT-INF/lib/* \
    -XX:+PrintCommandLineFlags \
    -XX:InitialRAMPercentage=70.0 \
    -XX:MinRAMPercentage=70.0 \
    -XX:MaxRAMPercentage=70.0 \
    -XX:+ExitOnOutOfMemoryError \
    -XX:+HeapDumpOnOutOfMemoryError \
    -XX:HeapDumpPath=/tmp/heapdump.hprof \
    -Djava.security.egd=file:/dev/./urandom \
    -Dspring.profiles.active=${SPRING_PROFILES_ACTIVE} \
    ${JAVA_OPTS} \
    ${MAIN_CLASS}"]

# Set default CMD arguments
CMD []
