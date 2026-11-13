// Package config loads runtime settings for sample-app from environment variables.
package config

import (
	"fmt"
	"strconv"
	"time"
)

// Config holds the validated runtime settings of the service.
type Config struct {
	Port          int
	Version       string
	DrainDelay    time.Duration
	ShutdownLimit time.Duration
}

// Getenv abstracts os.Getenv so the loader can be tested without touching the process environment.
type Getenv func(key string) string

// Load builds a Config from the given environment lookup. buildVersion is the value compiled into the
// binary and is used unless APP_VERSION overrides it. Malformed values are rejected, never ignored.
func Load(getenv Getenv, buildVersion string) (Config, error) {
	cfg := Config{
		Port:          8080,
		Version:       buildVersion,
		DrainDelay:    10 * time.Second,
		ShutdownLimit: 20 * time.Second,
	}

	if v := getenv("APP_PORT"); v != "" {
		port, err := strconv.Atoi(v)
		if err != nil || port < 1 || port > 65535 {
			return Config{}, fmt.Errorf("APP_PORT must be an integer between 1 and 65535, got %q", v)
		}
		cfg.Port = port
	}

	if v := getenv("APP_VERSION"); v != "" {
		cfg.Version = v
	}

	if v := getenv("SHUTDOWN_DRAIN_DELAY"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil || d < 0 {
			return Config{}, fmt.Errorf("SHUTDOWN_DRAIN_DELAY must be a non-negative duration, got %q", v)
		}
		cfg.DrainDelay = d
	}

	if v := getenv("SHUTDOWN_TIMEOUT"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil || d <= 0 {
			return Config{}, fmt.Errorf("SHUTDOWN_TIMEOUT must be a positive duration, got %q", v)
		}
		cfg.ShutdownLimit = d
	}

	return cfg, nil
}
