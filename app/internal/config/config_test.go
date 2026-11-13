package config

import (
	"testing"
	"time"
)

func envFrom(m map[string]string) Getenv {
	return func(key string) string { return m[key] }
}

func TestLoad(t *testing.T) {
	tests := []struct {
		name    string
		env     map[string]string
		want    Config
		wantErr bool
	}{
		{
			name: "defaults when env is empty",
			env:  map[string]string{},
			want: Config{Port: 8080, Version: "build-sha", DrainDelay: 10 * time.Second, ShutdownLimit: 20 * time.Second},
		},
		{
			name: "overrides apply",
			env: map[string]string{
				"APP_PORT":             "9000",
				"APP_VERSION":          "abc123",
				"SHUTDOWN_DRAIN_DELAY": "2s",
				"SHUTDOWN_TIMEOUT":     "5s",
			},
			want: Config{Port: 9000, Version: "abc123", DrainDelay: 2 * time.Second, ShutdownLimit: 5 * time.Second},
		},
		{
			name: "zero drain delay is allowed",
			env:  map[string]string{"SHUTDOWN_DRAIN_DELAY": "0s"},
			want: Config{Port: 8080, Version: "build-sha", DrainDelay: 0, ShutdownLimit: 20 * time.Second},
		},
		{name: "non numeric port", env: map[string]string{"APP_PORT": "http"}, wantErr: true},
		{name: "port out of range", env: map[string]string{"APP_PORT": "70000"}, wantErr: true},
		{name: "port zero", env: map[string]string{"APP_PORT": "0"}, wantErr: true},
		{name: "bad drain duration", env: map[string]string{"SHUTDOWN_DRAIN_DELAY": "ten"}, wantErr: true},
		{name: "negative drain delay", env: map[string]string{"SHUTDOWN_DRAIN_DELAY": "-1s"}, wantErr: true},
		{name: "zero shutdown timeout", env: map[string]string{"SHUTDOWN_TIMEOUT": "0s"}, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := Load(envFrom(tt.env), "build-sha")
			if (err != nil) != tt.wantErr {
				t.Fatalf("Load() error = %v, wantErr %v", err, tt.wantErr)
			}
			if !tt.wantErr && got != tt.want {
				t.Fatalf("Load() = %+v, want %+v", got, tt.want)
			}
		})
	}
}
