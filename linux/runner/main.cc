#include "my_application.h"

// Điểm vào Linux: tạo GtkApplication chứa Flutter engine rồi chuyển vòng lặp sự kiện cho GTK.
int main(int argc, char** argv) {
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
