package core

import (
	"context"
	"errors"
	"log/slog"
	"strings"
	"sync"
	"testing"
	"time"
)

var errSinkFailed = errors.New("sink failed")

// recordingHandler is a minimal slog.Handler that captures what it receives.
type recordingHandler struct {
	mu      sync.Mutex
	records []slog.Record
	enabled bool
	err     error
}

func (h *recordingHandler) Enabled(_ context.Context, _ slog.Level) bool { return h.enabled }

func (h *recordingHandler) Handle(_ context.Context, r slog.Record) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.records = append(h.records, r)
	return h.err
}

func (h *recordingHandler) WithAttrs(_ []slog.Attr) slog.Handler { return h }
func (h *recordingHandler) WithGroup(_ string) slog.Handler      { return h }

func (h *recordingHandler) count() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.records)
}

func TestHasOTLPDestination(t *testing.T) {
	scenarios := []struct {
		name     string
		env      map[string]string
		expected bool
	}{
		{"no destination", map[string]string{}, false},
		{"generic endpoint", map[string]string{"OTEL_EXPORTER_OTLP_ENDPOINT": "https://otlp.example"}, true},
		{"logs endpoint", map[string]string{"OTEL_EXPORTER_OTLP_LOGS_ENDPOINT": "https://otlp.example/v1/logs"}, true},
		// Regression guard for onboarding rule 5: telemetry must NOT be gated
		// on a single vendor's connection string. If this ever returns true,
		// removing the App Insights setting would silently kill OTLP export.
		{"app insights alone is not a destination", map[string]string{
			"APPLICATIONINSIGHTS_CONNECTION_STRING": "InstrumentationKey=00000000-0000-0000-0000-000000000000",
		}, false},
	}

	for _, s := range scenarios {
		t.Run(s.name, func(t *testing.T) {
			for k, v := range s.env {
				t.Setenv(k, v)
			}

			if got := hasOTLPDestination(); got != s.expected {
				t.Fatalf("expected %v, got %v", s.expected, got)
			}
		})
	}
}

func TestOTLPMinLevel(t *testing.T) {
	scenarios := []struct {
		raw      string
		expected slog.Level
	}{
		{"", slog.LevelDebug - 100},
		{"DEBUG", slog.LevelDebug},
		{"info", slog.LevelInfo},
		{"  warn  ", slog.LevelWarn},
		{"WARNING", slog.LevelWarn},
		{"ERROR", slog.LevelError},
		{"nonsense", slog.LevelDebug - 100},
	}

	for _, s := range scenarios {
		t.Run("level_"+s.raw, func(t *testing.T) {
			t.Setenv("PB_OTEL_MIN_LEVEL", s.raw)

			if got := otlpMinLevel(); got != s.expected {
				t.Fatalf("expected %v, got %v", s.expected, got)
			}
		})
	}
}

// The no-destination path is what every consumer of this fork hits who is not
// deploying to Azure. It must return the original handler untouched, so
// PocketBase logs exactly as upstream does.
func TestInitOTelLoggerWithoutDestinationIsPassthrough(t *testing.T) {
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
	t.Setenv("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT", "")

	app := NewBaseApp(BaseAppConfig{DataDir: t.TempDir()})
	local := &recordingHandler{enabled: true}

	if got := app.initOTelLogger(local); got != slog.Handler(local) {
		t.Fatalf("expected the original handler back, got %T", got)
	}
}

func TestFanoutHandlerWritesToBothSinks(t *testing.T) {
	local := &recordingHandler{enabled: true}
	remote := &recordingHandler{enabled: true}

	h := &fanoutHandler{local: local, remote: remote, minLevel: slog.LevelDebug - 100}

	rec := slog.NewRecord(time.Now(), slog.LevelInfo, "hello", 0)
	if err := h.Handle(context.Background(), rec); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if local.count() != 1 {
		t.Fatalf("expected 1 local record, got %d", local.count())
	}
	if remote.count() != 1 {
		t.Fatalf("expected 1 remote record, got %d", remote.count())
	}
}

// minLevel trims what crosses the wire without affecting local storage, so the
// dashboard keeps full detail while collector ingestion stays bounded.
func TestFanoutHandlerMinLevelOnlyFiltersRemote(t *testing.T) {
	local := &recordingHandler{enabled: true}
	remote := &recordingHandler{enabled: true}

	h := &fanoutHandler{local: local, remote: remote, minLevel: slog.LevelWarn}

	rec := slog.NewRecord(time.Now(), slog.LevelInfo, "below threshold", 0)
	if err := h.Handle(context.Background(), rec); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if local.count() != 1 {
		t.Fatalf("expected the local sink to receive the record, got %d", local.count())
	}
	if remote.count() != 0 {
		t.Fatalf("expected the remote sink to be skipped, got %d", remote.count())
	}
}

// The whole point of the second sink: a failing local sink must not stop the
// remote one. This is the exact shape of the 2026-06-12 auxiliary.db failure.
func TestFanoutHandlerLocalFailureStillReachesRemote(t *testing.T) {
	local := &recordingHandler{enabled: true, err: errSinkFailed}
	remote := &recordingHandler{enabled: true}

	h := &fanoutHandler{local: local, remote: remote, minLevel: slog.LevelDebug - 100}

	rec := slog.NewRecord(time.Now(), slog.LevelError, "database disk image is malformed", 0)
	err := h.Handle(context.Background(), rec)

	if err == nil || !strings.Contains(err.Error(), "sink failed") {
		t.Fatalf("expected the local error to surface, got %v", err)
	}
	if remote.count() != 1 {
		t.Fatalf("expected the remote sink to receive the record anyway, got %d", remote.count())
	}
}

func TestFanoutHandlerEnabledIsUnionOfSinks(t *testing.T) {
	h := &fanoutHandler{
		local:    &recordingHandler{enabled: false},
		remote:   &recordingHandler{enabled: true},
		minLevel: slog.LevelDebug - 100,
	}

	if !h.Enabled(context.Background(), slog.LevelInfo) {
		t.Fatal("expected enabled when only the remote sink is enabled")
	}

	h.minLevel = slog.LevelError
	if h.Enabled(context.Background(), slog.LevelInfo) {
		t.Fatal("expected disabled when the remote sink is gated out by minLevel")
	}
}
