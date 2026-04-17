#include <gtk/gtk.h>
#include <gio/gio.h>
#include <libayatana-appindicator/app-indicator.h>

#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define RUNRAT_FRAME_COUNT 6
#define RUNRAT_SAMPLE_INTERVAL_MS 1000
#define RUNRAT_ANIMATION_TICK_MS 25
#define RUNRAT_RELOAD_WARNING_WINDOW_US (2 * G_USEC_PER_SEC)

typedef struct {
  uint64_t user;
  uint64_t nice;
  uint64_t system;
  uint64_t idle;
  uint64_t iowait;
  uint64_t irq;
  uint64_t softirq;
  uint64_t steal;
} CpuCounters;

typedef struct {
  uint64_t received;
  uint64_t sent;
} NetworkCounters;

typedef struct {
  AppIndicator *indicator;
  GtkWidget *menu;
  GtkWidget *btop_item;
  gchar *icon_dir;
  gchar *frame_names[RUNRAT_FRAME_COUNT];
  gchar *summary_text;
  guint watcher_id;
  CpuCounters previous_cpu;
  NetworkCounters previous_network;
  gboolean has_previous_cpu;
  gboolean has_previous_network;
  gboolean tray_watcher_available;
  guint frame_index;
  guint elapsed_animation_ms;
  guint frame_duration_ms;
  double cpu_percent;
  double memory_percent;
  uint64_t upload_bytes_per_second;
  uint64_t download_bytes_per_second;
  gint64 last_btop_launch_us;
} RunRatApp;

static volatile sig_atomic_t should_quit = 0;
static gint64 suppress_scale_warning_until_us = 0;

static void handle_signal(int signum) {
  (void)signum;
  should_quit = 1;
}

static void suppress_reload_scale_warning(void) {
  suppress_scale_warning_until_us = g_get_monotonic_time() + RUNRAT_RELOAD_WARNING_WINDOW_US;
}

static void gtk_log_handler(
    const gchar *log_domain,
    GLogLevelFlags log_level,
    const gchar *message,
    gpointer user_data) {
  gboolean is_reload_scale_warning =
      (log_level & G_LOG_LEVEL_CRITICAL) != 0 &&
      g_strcmp0(log_domain, "Gtk") == 0 &&
      message != NULL &&
      strstr(message, "gtk_widget_get_scale_factor: assertion 'GTK_IS_WIDGET (widget)' failed") != NULL;

  if (is_reload_scale_warning && g_get_monotonic_time() <= suppress_scale_warning_until_us) {
    return;
  }

  g_log_default_handler(log_domain, log_level, message, user_data);
}

static gchar *resolve_icon_dir(void) {
  const char *env_dir = g_getenv("RUNRAT_ICON_DIR");
  if (env_dir != NULL && g_file_test(env_dir, G_FILE_TEST_IS_DIR)) {
    return g_strdup(env_dir);
  }

  if (g_file_test(RUNRAT_SOURCE_ICON_DIR, G_FILE_TEST_IS_DIR)) {
    return g_strdup(RUNRAT_SOURCE_ICON_DIR);
  }

  return g_strdup(RUNRAT_ICON_DIR);
}

static gboolean read_cpu_counters(CpuCounters *counters) {
  FILE *file = fopen("/proc/stat", "r");
  if (file == NULL) {
    return FALSE;
  }

  char line[512];
  if (fgets(line, sizeof(line), file) == NULL) {
    fclose(file);
    return FALSE;
  }
  fclose(file);

  unsigned long long user = 0;
  unsigned long long nice = 0;
  unsigned long long system = 0;
  unsigned long long idle = 0;
  unsigned long long iowait = 0;
  unsigned long long irq = 0;
  unsigned long long softirq = 0;
  unsigned long long steal = 0;

  int fields = sscanf(
      line,
      "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
      &user,
      &nice,
      &system,
      &idle,
      &iowait,
      &irq,
      &softirq,
      &steal);

  if (fields < 4) {
    return FALSE;
  }

  counters->user = user;
  counters->nice = nice;
  counters->system = system;
  counters->idle = idle;
  counters->iowait = iowait;
  counters->irq = irq;
  counters->softirq = softirq;
  counters->steal = steal;
  return TRUE;
}

static uint64_t cpu_total(const CpuCounters *counters) {
  return counters->user + counters->nice + counters->system + counters->idle +
         counters->iowait + counters->irq + counters->softirq + counters->steal;
}

static uint64_t cpu_idle(const CpuCounters *counters) {
  return counters->idle + counters->iowait;
}

static gboolean read_memory_percent(double *percent) {
  FILE *file = fopen("/proc/meminfo", "r");
  if (file == NULL) {
    return FALSE;
  }

  char line[512];
  uint64_t total_kb = 0;
  uint64_t available_kb = 0;

  while (fgets(line, sizeof(line), file) != NULL) {
    char key[64];
    unsigned long long value = 0;

    if (sscanf(line, "%63[^:]: %llu", key, &value) != 2) {
      continue;
    }

    if (strcmp(key, "MemTotal") == 0) {
      total_kb = value;
    } else if (strcmp(key, "MemAvailable") == 0) {
      available_kb = value;
    }
  }

  fclose(file);

  if (total_kb == 0 || available_kb > total_kb) {
    return FALSE;
  }

  *percent = ((double)(total_kb - available_kb) / (double)total_kb) * 100.0;
  return TRUE;
}

static gboolean read_network_counters(NetworkCounters *counters) {
  FILE *file = fopen("/proc/net/dev", "r");
  if (file == NULL) {
    return FALSE;
  }

  char line[512];
  unsigned int line_number = 0;
  uint64_t received_total = 0;
  uint64_t sent_total = 0;

  while (fgets(line, sizeof(line), file) != NULL) {
    line_number++;
    if (line_number <= 2) {
      continue;
    }

    char *colon = strchr(line, ':');
    if (colon == NULL) {
      continue;
    }

    *colon = '\0';
    char *name = g_strstrip(line);
    if (strcmp(name, "lo") == 0) {
      continue;
    }

    unsigned long long received = 0;
    unsigned long long sent = 0;
    int fields = sscanf(
        colon + 1,
        " %llu %*u %*u %*u %*u %*u %*u %*u %llu",
        &received,
        &sent);

    if (fields == 2) {
      received_total += received;
      sent_total += sent;
    }
  }

  fclose(file);

  counters->received = received_total;
  counters->sent = sent_total;
  return TRUE;
}

static gchar *format_rate(uint64_t bytes_per_second) {
  if (bytes_per_second >= 1024ULL * 1024ULL) {
    return g_strdup_printf("%.1f MB/s", (double)bytes_per_second / (1024.0 * 1024.0));
  }

  if (bytes_per_second >= 1024ULL) {
    return g_strdup_printf("%.1f KB/s", (double)bytes_per_second / 1024.0);
  }

  return g_strdup_printf("%" G_GUINT64_FORMAT " B/s", (guint64)bytes_per_second);
}

static guint frame_duration_for_cpu(double cpu_percent) {
  double speed = cpu_percent / 5.0;
  if (speed < 1.0) {
    speed = 1.0;
  }

  guint duration = (guint)(500.0 / speed);
  if (duration < RUNRAT_ANIMATION_TICK_MS) {
    duration = RUNRAT_ANIMATION_TICK_MS;
  }
  return duration;
}

static void update_indicator_summary(RunRatApp *app) {
  gchar *upload = format_rate(app->upload_bytes_per_second);
  gchar *download = format_rate(app->download_bytes_per_second);
  gchar *summary = g_strdup_printf(
      "RunRat\nCPU %.1f%%\nMemory %.1f%%\nDown %s / Up %s",
      app->cpu_percent,
      app->memory_percent,
      download,
      upload);

  g_free(app->summary_text);
  app->summary_text = summary;

  if (app->indicator != NULL) {
    app_indicator_set_title(app->indicator, app->summary_text);
  }

  g_free(upload);
  g_free(download);
}

static gboolean sample_metrics(gpointer data) {
  RunRatApp *app = data;

  CpuCounters cpu = {0};
  if (read_cpu_counters(&cpu)) {
    if (app->has_previous_cpu) {
      uint64_t previous_total = cpu_total(&app->previous_cpu);
      uint64_t current_total = cpu_total(&cpu);
      uint64_t previous_idle = cpu_idle(&app->previous_cpu);
      uint64_t current_idle = cpu_idle(&cpu);

      if (current_total > previous_total && current_idle >= previous_idle) {
        uint64_t total_delta = current_total - previous_total;
        uint64_t idle_delta = current_idle - previous_idle;
        app->cpu_percent = ((double)(total_delta - idle_delta) / (double)total_delta) * 100.0;
      }
    }

    app->previous_cpu = cpu;
    app->has_previous_cpu = TRUE;
  }

  double memory_percent = 0.0;
  if (read_memory_percent(&memory_percent)) {
    app->memory_percent = memory_percent;
  }

  NetworkCounters network = {0};
  if (read_network_counters(&network)) {
    if (app->has_previous_network) {
      app->download_bytes_per_second =
          network.received >= app->previous_network.received
              ? network.received - app->previous_network.received
              : 0;
      app->upload_bytes_per_second =
          network.sent >= app->previous_network.sent
              ? network.sent - app->previous_network.sent
              : 0;
    }

    app->previous_network = network;
    app->has_previous_network = TRUE;
  }

  app->frame_duration_ms = frame_duration_for_cpu(app->cpu_percent);
  update_indicator_summary(app);

  return G_SOURCE_CONTINUE;
}

static gboolean animate_icon(gpointer data) {
  RunRatApp *app = data;

  if (!app->tray_watcher_available) {
    return G_SOURCE_CONTINUE;
  }

  app->elapsed_animation_ms += RUNRAT_ANIMATION_TICK_MS;
  if (app->elapsed_animation_ms < app->frame_duration_ms) {
    return G_SOURCE_CONTINUE;
  }

  app->elapsed_animation_ms = 0;
  app->frame_index = (app->frame_index + 1) % RUNRAT_FRAME_COUNT;
  app_indicator_set_icon_full(
      app->indicator,
      app->frame_names[app->frame_index],
      app->summary_text != NULL ? app->summary_text : "RunRat");

  if (should_quit) {
    gtk_main_quit();
  }

  return G_SOURCE_CONTINUE;
}

static gboolean launch_first_available(const char *const *commands) {
  for (guint index = 0; commands[index] != NULL; index++) {
    GError *error = NULL;
    if (g_spawn_command_line_async(commands[index], &error)) {
      return TRUE;
    }
    g_clear_error(&error);
  }

  return FALSE;
}

static void launch_btop(void) {
  const char *custom_command = g_getenv("RUNRAT_BTOP_COMMAND");
  if (custom_command != NULL && custom_command[0] != '\0') {
    GError *error = NULL;
    if (g_spawn_command_line_async(custom_command, &error)) {
      return;
    }
    g_clear_error(&error);
  }

  const char *commands[] = {
      "xdg-terminal-exec btop",
      "alacritty -e btop",
      "kitty btop",
      "foot btop",
      "gnome-terminal -- btop",
      "xterm -e btop",
      NULL,
  };

  if (!launch_first_available(commands)) {
    g_warning("Unable to launch btop; set RUNRAT_BTOP_COMMAND to a terminal command");
  }
}

static void btop_activated(GtkMenuItem *item, gpointer data) {
  (void)item;
  (void)data;
  launch_btop();
}

static void menu_shown(GtkWidget *menu, gpointer data) {
  (void)menu;

  RunRatApp *app = data;
  gint64 now = g_get_monotonic_time();
  if (now - app->last_btop_launch_us < G_USEC_PER_SEC) {
    return;
  }

  app->last_btop_launch_us = now;
  launch_btop();
}

static void quit_activated(GtkMenuItem *item, gpointer data) {
  (void)item;
  (void)data;
  gtk_main_quit();
}

static GtkWidget *create_menu(RunRatApp *app) {
  GtkWidget *menu = gtk_menu_new();

  app->btop_item = gtk_menu_item_new_with_label("Open btop");
  GtkWidget *separator = gtk_separator_menu_item_new();
  GtkWidget *quit_item = gtk_menu_item_new_with_label("Quit");

  g_signal_connect(app->btop_item, "activate", G_CALLBACK(btop_activated), app);
  g_signal_connect(quit_item, "activate", G_CALLBACK(quit_activated), app);
  g_signal_connect(menu, "show", G_CALLBACK(menu_shown), app);

  gtk_menu_shell_append(GTK_MENU_SHELL(menu), app->btop_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), separator);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit_item);
  gtk_widget_show_all(menu);

  return menu;
}

static void status_watcher_appeared(
    GDBusConnection *connection,
    const gchar *name,
    const gchar *name_owner,
    gpointer data) {
  (void)connection;
  (void)name;
  (void)name_owner;

  RunRatApp *app = data;
  suppress_reload_scale_warning();
  app->tray_watcher_available = TRUE;
}

static void status_watcher_vanished(GDBusConnection *connection, const gchar *name, gpointer data) {
  (void)connection;
  (void)name;

  RunRatApp *app = data;
  suppress_reload_scale_warning();
  app->tray_watcher_available = FALSE;
}

static void runrat_app_init(RunRatApp *app) {
  memset(app, 0, sizeof(*app));

  app->frame_duration_ms = 500;
  app->tray_watcher_available = TRUE;
  app->icon_dir = resolve_icon_dir();
  app->summary_text = g_strdup("RunRat\nCollecting metrics");

  for (guint index = 0; index < RUNRAT_FRAME_COUNT; index++) {
    app->frame_names[index] = g_strdup_printf("runrat%u", index);
  }

  app->menu = create_menu(app);
  app->watcher_id = g_bus_watch_name(
      G_BUS_TYPE_SESSION,
      "org.kde.StatusNotifierWatcher",
      G_BUS_NAME_WATCHER_FLAGS_NONE,
      status_watcher_appeared,
      status_watcher_vanished,
      app,
      NULL);

#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#endif
  app->indicator = app_indicator_new_with_path(
      "runrat",
      app->frame_names[0],
      APP_INDICATOR_CATEGORY_SYSTEM_SERVICES,
      app->icon_dir);
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif
  app_indicator_set_icon_full(app->indicator, app->frame_names[0], app->summary_text);
  app_indicator_set_menu(app->indicator, GTK_MENU(app->menu));
  app_indicator_set_secondary_activate_target(app->indicator, app->btop_item);
  app_indicator_set_title(app->indicator, app->summary_text);
  app_indicator_set_status(app->indicator, APP_INDICATOR_STATUS_ACTIVE);

  sample_metrics(app);
  g_timeout_add(RUNRAT_SAMPLE_INTERVAL_MS, sample_metrics, app);
  g_timeout_add(RUNRAT_ANIMATION_TICK_MS, animate_icon, app);
}

static void runrat_app_clear(RunRatApp *app) {
  if (app->watcher_id != 0) {
    g_bus_unwatch_name(app->watcher_id);
  }

  if (app->indicator != NULL) {
    app_indicator_set_status(app->indicator, APP_INDICATOR_STATUS_PASSIVE);
    g_object_unref(app->indicator);
  }

  if (app->menu != NULL) {
    gtk_widget_destroy(app->menu);
  }

  for (guint index = 0; index < RUNRAT_FRAME_COUNT; index++) {
    g_free(app->frame_names[index]);
  }

  g_free(app->summary_text);
  g_free(app->icon_dir);
}

int main(int argc, char **argv) {
  signal(SIGINT, handle_signal);
  signal(SIGTERM, handle_signal);
  g_log_set_handler("Gtk", G_LOG_LEVEL_CRITICAL, gtk_log_handler, NULL);

  gtk_init(&argc, &argv);

  RunRatApp app;
  runrat_app_init(&app);

  gtk_main();

  runrat_app_clear(&app);
  return EXIT_SUCCESS;
}
