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
 * 建立一個基於 Flutter 的新應用程式。
 *
 * 傳回值：一個新的 #MyApplication。
 */
MyApplication* my_application_new();

#endif  // FLUTTER_MY_APPLICATION_H_
