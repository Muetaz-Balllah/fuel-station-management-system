import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/features/dashboard/data/models/dashboard_models.dart';
import 'package:frontend/features/dashboard/data/repos/dashboard_repository.dart';

class NotificationState {
  const NotificationState({this.loaded = false, this.items = const []});

  final bool loaded;
  final List<StationNotice> items;

  int get unread => items.where((item) => item.unread).length;

  NotificationState copyWith({bool? loaded, List<StationNotice>? items}) {
    return NotificationState(loaded: loaded ?? this.loaded, items: items ?? this.items);
  }
}

class NotificationCubit extends Cubit<NotificationState> {
  NotificationCubit(this._repository, {NotificationState? initial}) : super(initial ?? const NotificationState());

  final DashboardRepository _repository;

  Future<void> load() async {
    try {
      final items = await _repository.notifications();
      emit(NotificationState(loaded: true, items: items));
    } catch (_) {
      emit(state.copyWith(loaded: true));
    }
  }

  Future<void> markRead(String id) async {
    await _repository.markRead(id);
    emit(
      state.copyWith(
        items: [
          for (final item in state.items)
            if (item.id == id)
              StationNotice(id: item.id, kind: item.kind, title: item.title, body: item.body, readAt: 'read')
            else
              item,
        ],
      ),
    );
  }
}
