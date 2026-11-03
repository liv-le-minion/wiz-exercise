# syntax=docker/dockerfile:1

# ---------- Build stage: compile the Go app ----------
FROM --platform=$BUILDPLATFORM golang:1.23-alpine AS build
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /out/tasky .

# ---------- Runtime stage: small final image ----------
FROM alpine:3.20
WORKDIR /app
COPY --from=build /out/tasky ./tasky
COPY assets ./assets

# Exercise requirement: wizexercise.txt containing the candidate's name
COPY wizexercise.txt /app/wizexercise.txt

EXPOSE 8080
ENTRYPOINT ["/app/tasky"]
