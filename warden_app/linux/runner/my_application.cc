#include "my_application.h"

#include <cerrno>
#include <fcntl.h>
#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  int instance_lock_fd;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

enum class InstanceLockResult { kAcquired, kAlreadyRunning, kError };

static InstanceLockResult acquire_instance_lock(MyApplication* self) {
  const gchar* user_data_root = g_get_user_data_dir();
  if (user_data_root == nullptr || user_data_root[0] == '\0') {
    return InstanceLockResult::kError;
  }

  g_autofree gchar* lock_directory =
      g_build_filename(user_data_root, APPLICATION_ID, nullptr);
  if (g_mkdir_with_parents(lock_directory, 0700) != 0) {
    return InstanceLockResult::kError;
  }

  struct stat directory_status {};
  if (lstat(lock_directory, &directory_status) != 0 ||
      !S_ISDIR(directory_status.st_mode) ||
      directory_status.st_uid != geteuid() ||
      chmod(lock_directory, 0700) != 0) {
    return InstanceLockResult::kError;
  }

  g_autofree gchar* lock_path =
      g_build_filename(lock_directory, "instance.lock", nullptr);
  const int lock_fd =
      open(lock_path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (lock_fd < 0) {
    return InstanceLockResult::kError;
  }

  struct stat lock_status {};
  if (fstat(lock_fd, &lock_status) != 0 ||
      !S_ISREG(lock_status.st_mode) || lock_status.st_uid != geteuid() ||
      fchmod(lock_fd, 0600) != 0) {
    close(lock_fd);
    return InstanceLockResult::kError;
  }

  if (flock(lock_fd, LOCK_EX | LOCK_NB) == 0) {
    self->instance_lock_fd = lock_fd;
    return InstanceLockResult::kAcquired;
  }

  const int lock_error = errno;
  close(lock_fd);
  if (lock_error == EWOULDBLOCK || lock_error == EAGAIN) {
    return InstanceLockResult::kAlreadyRunning;
  }
  return InstanceLockResult::kError;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows != nullptr) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Wcash Warden Testnet");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Wcash Warden Testnet");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  // GApplication uniqueness is scoped to one D-Bus session. The advisory
  // lock closes the remaining multi-session race before Flutter or any secure
  // storage plugin is started. Remote launches in the same session skip this
  // lock and activate the existing window below.
  if (!g_application_get_is_remote(application) &&
      self->instance_lock_fd < 0) {
    const InstanceLockResult lock_result = acquire_instance_lock(self);
    if (lock_result != InstanceLockResult::kAcquired) {
      *exit_status = lock_result == InstanceLockResult::kAlreadyRunning ? 0 : 1;
      return TRUE;
    }
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  if (self->instance_lock_fd >= 0) {
    close(self->instance_lock_fd);
    self->instance_lock_fd = -1;
  }
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->instance_lock_fd = -1;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

#if GLIB_CHECK_VERSION(2, 74, 0)
  constexpr GApplicationFlags application_flags = G_APPLICATION_DEFAULT_FLAGS;
#else
  constexpr GApplicationFlags application_flags = G_APPLICATION_FLAGS_NONE;
#endif
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     application_flags, nullptr));
}
