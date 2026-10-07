import 'package:todo_example/todo.g.dart';
import 'package:todo_shared/testing.dart';

void main() {
  testWrapperEmbedsCurrentSlint(TodoApp.slintSource, TodoApp.slintFiles);
}
