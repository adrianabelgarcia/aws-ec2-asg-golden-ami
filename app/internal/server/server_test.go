package server

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func newTestServer(t *testing.T) (*Server, *bytes.Buffer) {
	t.Helper()
	buf := &bytes.Buffer{}
	logger := slog.New(slog.NewJSONHandler(buf, nil))
	return New("test-version", logger), buf
}

func TestRoutes(t *testing.T) {
	tests := []struct {
		name       string
		method     string
		path       string
		draining   bool
		wantStatus int
		wantBody   string
	}{
		{name: "health ok", method: http.MethodGet, path: "/health", wantStatus: http.StatusOK, wantBody: `"status":"ok"`},
		{name: "health draining", method: http.MethodGet, path: "/health", draining: true, wantStatus: http.StatusServiceUnavailable, wantBody: `"status":"draining"`},
		{name: "version", method: http.MethodGet, path: "/version", wantStatus: http.StatusOK, wantBody: `"version":"test-version"`},
		{name: "root", method: http.MethodGet, path: "/", wantStatus: http.StatusOK, wantBody: `"service":"sample-app"`},
		{name: "unknown path", method: http.MethodGet, path: "/nope", wantStatus: http.StatusNotFound},
		{name: "wrong method on health", method: http.MethodPost, path: "/health", wantStatus: http.StatusMethodNotAllowed},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv, _ := newTestServer(t)
			if tt.draining {
				srv.StartDraining()
			}
			rec := httptest.NewRecorder()
			srv.Handler().ServeHTTP(rec, httptest.NewRequest(tt.method, tt.path, nil))

			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d", rec.Code, tt.wantStatus)
			}
			if tt.wantBody != "" && !strings.Contains(rec.Body.String(), tt.wantBody) {
				t.Fatalf("body = %q, want it to contain %q", rec.Body.String(), tt.wantBody)
			}
		})
	}
}

func TestHealthResponseIsJSONAndNotCached(t *testing.T) {
	srv, _ := newTestServer(t)
	rec := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))

	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Errorf("Content-Type = %q, want application/json", got)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Errorf("Cache-Control = %q, want no-store", got)
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("body is not valid JSON: %v", err)
	}
}

func TestDrainingFlipsHealthAndIsSticky(t *testing.T) {
	srv, _ := newTestServer(t)
	if srv.Draining() {
		t.Fatal("new server should not be draining")
	}
	srv.StartDraining()
	srv.StartDraining()
	if !srv.Draining() {
		t.Fatal("server should be draining after StartDraining")
	}
}

func TestRequestLogContainsStatusAndPath(t *testing.T) {
	srv, buf := newTestServer(t)
	rec := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/nope", nil))

	line := buf.String()
	for _, want := range []string{`"msg":"request"`, `"path":"/nope"`, `"status":404`, `"method":"GET"`} {
		if !strings.Contains(line, want) {
			t.Errorf("log line %q does not contain %q", line, want)
		}
	}
}
