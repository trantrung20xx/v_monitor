#ifndef FLUTTER_MY_APPLICATION_H_
#define FLUTTER_MY_APPLICATION_H_

#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(MyApplication,
                     my_application,
                     MY,
                     APPLICATION,
                     GtkApplication)

/**
 * my_application_new:
 *
 * Tạo một ứng dụng GTK làm host cho Flutter.
 *
 * Trả về: một instance #MyApplication mới.
 */
MyApplication* my_application_new();

#endif  // FLUTTER_MY_APPLICATION_H_
