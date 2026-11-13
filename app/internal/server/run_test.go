package server

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"testing"
	"time"
)

func TestServeDrainsBeforeShutdown(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	app := New("v-test", logger)

	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	base := fmt.Sprintf("http://%s", l.Addr().String())

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- Serve(ctx, l, app, RunOptions{
			ReadHeaderTimeout: time.Second,
			DrainDelay:        200 * time.Millisecond,
			ShutdownTimeout:   2 * time.Second,
		}, logger)
	}()

	client := &http.Client{Timeout: time.Second}
	resp, err := client.Get(base + "/health")
	if err != nil {
		t.Fatalf("health before drain: %v", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("health before drain = %d, want 200", resp.StatusCode)
	}

	cancel()

	// During the drain delay the health check must already report 503.
	deadline := time.Now().Add(150 * time.Millisecond)
	for time.Now().Before(deadline) && !app.Draining() {
		time.Sleep(5 * time.Millisecond)
	}
	if !app.Draining() {
		t.Fatal("server did not enter draining state after context cancel")
	}

	if err := <-done; err != nil {
		t.Fatalf("Serve returned error: %v", err)
	}
}

func TestServeReturnsListenerError(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	_ = l.Close() // a closed listener makes Serve fail immediately

	err = Serve(context.Background(), l, New("v", logger), RunOptions{ShutdownTimeout: time.Second}, logger)
	if err == nil {
		t.Fatal("expected error from closed listener")
	}
}
