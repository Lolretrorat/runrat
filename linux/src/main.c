#include <gtk/gtk.h>
#include <libayatana-appindicator/app-indicator.h>

#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define RUNRAT_FRAME_COUNT 6
#define RUNRAT_SAMPLE_INTERVAL_MS 1000
#define RUNRAT_ANIMATION_TICK_MS 25

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
  GtkWidget *cpu_item;
  GtkWidget *memory_item;
  GtkWidget *network_item;
  gchar *icon_dir;
  gchar *frame_names[RUNRAT_FRAME_COUNT];
  CpuCounters previous_cpu;
  NetworkCounters previous_network;
  gboolean has_previous_cpu;
  gboolean has_previous_network;
  guint frame_index;
  guint elapsed_animation_ms;
  guint frame_duration_ms;
  double cpu_percent;
  double memory_percent;
  uint64_t upload_bytes_per_second;
  uint64_t download_bytes_per_second;
} RunRatApp;

static volatile sig_atomic_t should_quit = 0;

static void handle_signal(int signum) {
  (void)signum;
  should_quit = 1;
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

static void set_menu_item_label(GtkWidget *item, const char *label) {
  gtk_menu_item_set_label(GTK_MENU_ITEM(item), label);
}

static void update_menu_labels(RunRatApp *app) {
  gchar *upload = format_rate(app->upload_bytes_per_second);
  gchar *download = format_rate(app->download_bytes_per_second);
  gchar *cpu = g_strdup_printf("CPU: %.1f%%", app->cpu_percent);
  gchar *memory = g_strdup_printf("Memory: %.1f%%", app->memory_percent);
  gchar *network = g_strdup_printf("Network: %s up / %s down", upload, download);

  set_menu_item_label(app->cpu_item, cpu);
  set_menu_item_label(app->memory_item, memory);
  set_menu_item_label(app->network_item, network);

  g_free(upload);
  g_free(download);
  g_free(cpu);
  g_free(memory);
  g_free(network);
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
  update_menu_labels(app);

  return G_SOURCE_CONTINUE;
}

static gboolean animate_icon(gpointer data) {
  RunRatApp *app = data;

  app->elapsed_animation_ms += RUNRAT_ANIMATION_TICK_MS;
  if (app->elapsed_animation_ms < app->frame_duration_ms) {
    return G_SOURCE_CONTINUE;
  }

  app->elapsed_animation_ms = 0;
  app->frame_index = (app->frame_index + 1) % RUNRAT_FRAME_COUNT;
  app_indicator_set_icon_full(app->indicator, app->frame_names[app->frame_index], "RunRat");

  if (should_quit) {
    gtk_main_quit();
  }

  return G_SOURCE_CONTINUE;
}

static void quit_activated(GtkMenuItem *item, gpointer data) {
  (void)item;
  (void)data;
  gtk_main_quit();
}

static GtkWidget *create_menu(RunRatApp *app) {
  GtkWidget *menu = gtk_menu_new();

  app->cpu_item = gtk_menu_item_new_with_label("CPU: --");
  app->memory_item = gtk_menu_item_new_with_label("Memory: --");
  app->network_item = gtk_menu_item_new_with_label("Network: --");
  GtkWidget *separator = gtk_separator_menu_item_new();
  GtkWidget *quit_item = gtk_menu_item_new_with_label("Quit");

  gtk_widget_set_sensitive(app->cpu_item, FALSE);
  gtk_widget_set_sensitive(app->memory_item, FALSE);
  gtk_widget_set_sensitive(app->network_item, FALSE);

  g_signal_connect(quit_item, "activate", G_CALLBACK(quit_activated), app);

  gtk_menu_shell_append(GTK_MENU_SHELL(menu), app->cpu_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), app->memory_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), app->network_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), separator);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit_item);
  gtk_widget_show_all(menu);

  return menu;
}

static void runrat_app_init(RunRatApp *app) {
  memset(app, 0, sizeof(*app));

  app->frame_duration_ms = 500;
  app->icon_dir = resolve_icon_dir();

  for (guint index = 0; index < RUNRAT_FRAME_COUNT; index++) {
    app->frame_names[index] = g_strdup_printf("runrat%u", index);
  }

  app->menu = create_menu(app);

  app->indicator = app_indicator_new(
      "runrat",
      app->frame_names[0],
      APP_INDICATOR_CATEGORY_SYSTEM_SERVICES);
  app_indicator_set_icon_theme_path(app->indicator, app->icon_dir);
  app_indicator_set_icon_full(app->indicator, app->frame_names[0], "RunRat");
  app_indicator_set_menu(app->indicator, GTK_MENU(app->menu));
  app_indicator_set_status(app->indicator, APP_INDICATOR_STATUS_ACTIVE);

  sample_metrics(app);
  g_timeout_add(RUNRAT_SAMPLE_INTERVAL_MS, sample_metrics, app);
  g_timeout_add(RUNRAT_ANIMATION_TICK_MS, animate_icon, app);
}

static void runrat_app_clear(RunRatApp *app) {
  if (app->indicator != NULL) {
    g_object_unref(app->indicator);
  }

  if (app->menu != NULL) {
    gtk_widget_destroy(app->menu);
  }

  for (guint index = 0; index < RUNRAT_FRAME_COUNT; index++) {
    g_free(app->frame_names[index]);
  }

  g_free(app->icon_dir);
}

int main(int argc, char **argv) {
  signal(SIGINT, handle_signal);
  signal(SIGTERM, handle_signal);

  gtk_init(&argc, &argv);

  RunRatApp app;
  runrat_app_init(&app);

  gtk_main();

  runrat_app_clear(&app);
  return EXIT_SUCCESS;
}
