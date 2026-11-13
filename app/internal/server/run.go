package server

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"time"
)

// RunOptions controls the serve loop and the shutdown sequence.
type RunOptions struct {
	ReadHeaderTimeout time.Duration
	DrainDelay        time.Duration
	ShutdownTimeout   time.Duration
}

// Serve accepts connections on l until ctx is cancelled. On cancellation it first marks the
// server as draining (so /health returns 503 and the ALB deregisters the target), waits
// DrainDelay for that to take effect, and then shuts down gracefully within ShutdownTimeout.
func Serve(ctx context.Context, l net.Listener, app *Server, opts RunOptions, logger *slog.Logger) error {
	httpServer := &http.Server{
		Handler:           app.Handler(),
		ReadHeaderTimeout: opts.ReadHeaderTimeout,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		// Must exceed the ALB idle timeout (60s). A shorter keep-alive lets the ALB reuse a socket the
		// app has already closed, which surfaces as intermittent 502s.
		IdleTimeout: 75 * time.Second,
	}

	serveErr := make(chan error, 1)
	go func() {
		serveErr <- httpServer.Serve(l)
	}()

	select {
	case err := <-serveErr:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-ctx.Done():
	}

	logger.Info("shutdown requested, draining", slog.Duration("drain_delay", opts.DrainDelay))
	app.StartDraining()
	time.Sleep(opts.DrainDelay)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), opts.ShutdownTimeout)
	defer cancel()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("graceful shutdown failed: %w", err)
	}
	logger.Info("shutdown complete")
	return nil
}
