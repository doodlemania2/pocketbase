package core

// Fork-local addition — not upstream PocketBase.
//
// Exports records written through app.Logger() to an OTLP collector in addition
// to the SQLite `_logs` sink, so telemetry survives the auxiliary database.
// This matters concretely: auxiliary.db corrupted on 2026-06-12 and every
// request log was silently dropped until 2026-08-15, because the batch writer
// in initLogger swallows per-row write errors. A second, independent sink makes
// that failure visible the day it happens.
//
// Wire contract: docs/observability/otlp-onboarding.md in the STFoA-Church
// repo. Load-bearing points:
//
//   - OTLP/HTTP only. The collector sits behind a Cloudflare Tunnel carrying
//     HTTP; gRPC on 4317 never arrives. The deployment must set
//     OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf.
//   - Staging and production post to the same collector with the same token, so
//     resource attributes are the only thing telling them apart.
//   - Gate on the destination set, never on one vendor's connection string
//     (onboarding rule 5). Removing App Insights must not silence OTLP.
//
// Opt-in: with no OTLP endpoint configured this changes nothing.

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"strings"

	"go.opentelemetry.io/contrib/bridges/otelslog"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp"
	otellog "go.opentelemetry.io/otel/sdk/log"
	"go.opentelemetry.io/otel/sdk/resource"

	"github.com/pocketbase/pocketbase/tools/hook"
)

const (
	// OTelLoggerShutdownHookId is the id of the OnTerminate hook that flushes
	// and shuts down the OTLP log pipeline.
	OTelLoggerShutdownHookId = "__pbOTelLoggerShutdown__"

	// defaultOTelServiceName applies only when the deployment sets neither
	// OTEL_SERVICE_NAME nor a service.name in OTEL_RESOURCE_ATTRIBUTES.
	defaultOTelServiceName = "stfoa-auth"

	// defaultOTelServiceNamespace groups the parish apps in SigNoz.
	defaultOTelServiceNamespace = "stfoa"

	// otelScopeName identifies the emitting library on every record.
	otelScopeName = "github.com/pocketbase/pocketbase/core"
)

// hasOTLPDestination reports whether an OTLP collector is configured.
//
// Checks the generic and logs-specific endpoints and nothing else. It does NOT
// consider APPLICATIONINSIGHTS_CONNECTION_STRING: gating telemetry on one
// vendor's setting is the trap the onboarding spec calls out, where removing
// that setting silently stops every export while the collector sits healthy.
func hasOTLPDestination() bool {
	return os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") != "" ||
		os.Getenv("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT") != ""
}

// otlpMinLevel returns the minimum level exported to OTLP.
//
// Request logging is high volume — a 10s health probe alone is ~8.6k records a
// day — and ingestion is not free. PB_OTEL_MIN_LEVEL trims what crosses the
// wire without touching what PocketBase stores locally, so the dashboard keeps
// full detail either way.
func otlpMinLevel() slog.Level {
	switch strings.ToUpper(strings.TrimSpace(os.Getenv("PB_OTEL_MIN_LEVEL"))) {
	case "DEBUG":
		return slog.LevelDebug
	case "INFO":
		return slog.LevelInfo
	case "WARN", "WARNING":
		return slog.LevelWarn
	case "ERROR":
		return slog.LevelError
	default:
		return slog.LevelDebug - 100 // effectively unfiltered
	}
}

// newOTelResource builds the resource every exported record carries.
//
// resource.WithFromEnv() reads OTEL_SERVICE_NAME and OTEL_RESOURCE_ATTRIBUTES,
// which is how the deployment supplies service.name, service.namespace and both
// deployment.environment spellings. The defaults only fill gaps, so an
// unconfigured app never lands in SigNoz as "unknown_service".
func newOTelResource(ctx context.Context) (*resource.Resource, error) {
	base, err := resource.New(ctx,
		resource.WithFromEnv(),
		resource.WithTelemetrySDK(),
	)
	if err != nil {
		return nil, err
	}

	var hasServiceName, hasNamespace bool
	for _, attr := range base.Attributes() {
		switch string(attr.Key) {
		case "service.name":
			// WithFromEnv substitutes a synthetic "unknown_service:<binary>"
			// when nothing is configured; treat that as absent.
			hasServiceName = !strings.HasPrefix(attr.Value.AsString(), "unknown_service")
		case "service.namespace":
			hasNamespace = true
		}
	}

	fallbacks := []attribute.KeyValue{}
	if !hasServiceName {
		fallbacks = append(fallbacks, attribute.String("service.name", defaultOTelServiceName))
	}
	if !hasNamespace {
		fallbacks = append(fallbacks, attribute.String("service.namespace", defaultOTelServiceNamespace))
	}
	if len(fallbacks) == 0 {
		return base, nil
	}

	defaults, err := resource.New(ctx, resource.WithAttributes(fallbacks...))
	if err != nil {
		return nil, err
	}

	// base wins on conflict — a configured value is never overridden.
	return resource.Merge(defaults, base)
}

// initOTelLogger wraps the local slog handler with an OTLP exporter when a
// collector is configured, and registers the flush-on-terminate hook.
//
// Returns the handler unchanged when no destination is set, so the
// non-exporting path costs nothing and cannot fail.
func (app *BaseApp) initOTelLogger(local slog.Handler) slog.Handler {
	if !hasOTLPDestination() {
		return local
	}

	ctx := context.Background()

	res, err := newOTelResource(ctx)
	if err != nil {
		// Never let telemetry setup take down the app.
		fmt.Fprintf(os.Stderr, "[otel] resource init failed, OTLP export disabled: %v\n", err)
		return local
	}

	// The exporter reads OTEL_EXPORTER_OTLP_{ENDPOINT,PROTOCOL,HEADERS} itself,
	// which is why repointing the collector needs no code change.
	exporter, err := otlploghttp.New(ctx)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[otel] exporter init failed, OTLP export disabled: %v\n", err)
		return local
	}

	provider := otellog.NewLoggerProvider(
		otellog.WithResource(res),
		otellog.WithProcessor(otellog.NewBatchProcessor(exporter)),
	)

	// Route SDK-internal errors to stderr. Container Apps already ships
	// stdout/stderr to Log Analytics, so a broken exporter stays visible there
	// — and this keeps exporter failures OFF app.Logger(), which would
	// otherwise feed them straight back into this handler.
	otel.SetErrorHandler(otel.ErrorHandlerFunc(func(err error) {
		fmt.Fprintf(os.Stderr, "[otel] %v\n", err)
	}))

	app.OnTerminate().Bind(&hook.Handler[*TerminateEvent]{
		Id: OTelLoggerShutdownHookId,
		Func: func(e *TerminateEvent) error {
			// Flush before the process goes away, otherwise the last batch —
			// often the one explaining the shutdown — is lost.
			if err := provider.Shutdown(context.Background()); err != nil {
				fmt.Fprintf(os.Stderr, "[otel] shutdown: %v\n", err)
			}

			return e.Next()
		},
	})

	return &fanoutHandler{
		local:    local,
		remote:   otelslog.NewHandler(otelScopeName, otelslog.WithLoggerProvider(provider)),
		minLevel: otlpMinLevel(),
	}
}

// fanoutHandler writes every record to the local sink and, when it clears
// minLevel, to the OTLP sink as well.
//
// The sinks are independent on purpose: a failure in either must not suppress
// the other. That independence is the point — the local sink going silent is
// precisely the failure this file exists to surface.
type fanoutHandler struct {
	local    slog.Handler
	remote   slog.Handler
	minLevel slog.Level
}

func (h *fanoutHandler) Enabled(ctx context.Context, level slog.Level) bool {
	return h.local.Enabled(ctx, level) || (level >= h.minLevel && h.remote.Enabled(ctx, level))
}

func (h *fanoutHandler) Handle(ctx context.Context, record slog.Record) error {
	// Errors are collected rather than short-circuited, so one failing sink
	// still lets the other receive the record.
	var firstErr error

	if h.local.Enabled(ctx, record.Level) {
		if err := h.local.Handle(ctx, record.Clone()); err != nil {
			firstErr = err
		}
	}

	if record.Level >= h.minLevel && h.remote.Enabled(ctx, record.Level) {
		if err := h.remote.Handle(ctx, record.Clone()); err != nil && firstErr == nil {
			firstErr = err
		}
	}

	return firstErr
}

func (h *fanoutHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return &fanoutHandler{
		local:    h.local.WithAttrs(attrs),
		remote:   h.remote.WithAttrs(attrs),
		minLevel: h.minLevel,
	}
}

func (h *fanoutHandler) WithGroup(name string) slog.Handler {
	return &fanoutHandler{
		local:    h.local.WithGroup(name),
		remote:   h.remote.WithGroup(name),
		minLevel: h.minLevel,
	}
}
