// Package server implements the HTTP surface of sample-app: a health endpoint used by the
// ALB target group, a version endpoint, and structured request logging.
package server

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"sync/atomic"
	"time"
)

// Server is the HTTP handler set. Draining is flipped on SIGTERM so the ALB stops routing
// new requests before the process stops accepting connections.
type Server struct {
	version  string
	logger   *slog.Logger
	draining atomic.Bool
}

// New returns a Server reporting the given version and logging through logger.
func New(version string, logger *slog.Logger) *Server {
	return &Server{version: version, logger: logger}
}

// StartDraining marks the instance as unhealthy so load balancers deregister it.
func (s *Server) StartDraining() {
	s.draining.Store(true)
}

// Draining reports whether StartDraining has been called.
func (s *Server) Draining() bool {
	return s.draining.Load()
}

// Handler returns the routed and logged HTTP handler.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.HandleFunc("GET /version", s.handleVersion)
	mux.HandleFunc("GET /{$}", s.handleRoot)
	return s.logRequests(mux)
}

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	if s.Draining() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "draining"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleVersion(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"version": s.version})
}

func (s *Server) handleRoot(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"service": "sample-app",
		"version": s.version,
	})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body) // headers are already sent; nothing useful to do on error
}

// statusRecorder captures the status code written by a downstream handler.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (s *Server) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		s.logger.Info("request",
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
			slog.Int("status", rec.status),
			slog.Float64("duration_ms", float64(time.Since(start).Microseconds())/1000),
		)
	})
}
