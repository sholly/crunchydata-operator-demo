create table if not exists todoitems(
    id SERIAL,
    name VARCHAR(40),
    description text,
    finished boolean
    );

insert into todoitems(id, name, description, finished) values (1, 'Learn Openshift Admin', 'I need to learn Openshift Admin', false);
insert into todoitems(id, name, description, finished) values (2, 'Learn Tekton', 'I need to learn Tekton', false);
insert into todoitems(id, name, description, finished) values (3, 'Take a vacation', 'All work and no play', false);