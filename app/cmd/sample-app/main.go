// Command sample-app is a small HTTP service used to exercise the golden AMI and ASG rollout
// pipeline. It drains gracefully on SIGTERM so instance refresh does not drop in-flight requests.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/adrianabelgarcia/aws-ec2-asg-golden-ami/app/internal/config"
	"github.com/adrianabelgarcia/aws-ec2-asg-golden-ami/app/internal/server"
)

// buildVersion is injected at build time with -ldflags "-X main.buildVersion=<git sha>".
var buildVersion = "dev"

func main() {
	if err := run(); err != nil {
		slog.Error("sample-app exited with error", slog.String("error", err.Error()))
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load(os.Getenv, buildVersion)
	if err != nil {
		return fmt.Errorf("invalid configuration: %w", err)
	}

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	listener, err := net.Listen("tcp", fmt.Sprintf(":%d", cfg.Port))
	if err != nil {
		return fmt.Errorf("listen on port %d: %w", cfg.Port, err)
	}
	logger.Info("listening", slog.Int("port", cfg.Port), slog.String("version", cfg.Version))

	return server.Serve(ctx, listener, server.New(cfg.Version, logger), server.RunOptions{
		ReadHeaderTimeout: 5 * time.Second,
		DrainDelay:        cfg.DrainDelay,
		ShutdownTimeout:   cfg.ShutdownLimit,
	}, logger)
}
