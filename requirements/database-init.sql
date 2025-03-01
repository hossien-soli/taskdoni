/* each time we run this file we have a fresh database for system! */

drop table if exists users;
drop table if exists refresh_tokens;
drop table if exists refresh_token_families;
drop table if exists projects;
drop table if exists projects_users;
drop table if exists tasks;

create table users
(
    id                int unsigned not null auto_increment, /* long */

    name              varchar(35)  not null, /* full_name */

    email             varchar(50)  not null,
    username          varchar(25)  not null, /* min:5 */
    password          varchar(255) not null, /* hashed password / min:8 */

    role              tinyint      not null, /* 1=CLIENT, 2=MODERATOR, 3=ADMIN  mapped to enum in java */
    /* clients are normal users that can register in system with public registration form! */

    banned            bit(1)       not null default 0, /* boolean - user was banned by a moderator or admin! */
    /* banned users can't create new projects and invite other to a project  */

    registered_at     datetime     not null,
    email_verified_at datetime     null,

    primary key (id),
    unique (email),
    unique (username)
);

/* we have a scheduled task for deleting records of old expired,revoked,invalidated families */
/* in fact this families are the sessions of the users */
/* oldest active token family bearer(created_at) can revoke other token families or sessions of user */
create table refresh_token_families
(
    id             bigint       not null auto_increment, /* java-long */
    user           int unsigned not null,
    revoked        bit(1)       not null default 0,
    expired        bit(1)       not null default 0, /* when last token expires this will set to true */
    invalidated    bit(1)       not null default 0, /* family invalidated due to reuse detection */

    created_at     datetime     not null,
    closed_at      datetime     null, /* fill after revocation or expiration or invalidation */

    /* oldest active token family bearer(created_at) can revoke other token families or sessions of user */

    user_agent     text         null, /* max:1000 */
    ip_address     varchar(50)  null,
    ip_lookup_info tinytext     null, /* country,city,province,state */

    primary key (id),
    foreign key (user) references users (id) on delete cascade on update cascade
);

/* before each refresh and requesting new access token family must also check for expiration,revocation,invalidation */
create table refresh_tokens
(
    token        varchar(255)     not null,
    family       bigint           not null, /* java-long */

    lifetime     tinyint unsigned not null, /* 1-255 days */
    refreshed    bit(1)           not null default 0, /* used for reuse detection */

    created_at   datetime         not null, /* check expiration of family and token base on this (last token) */
    refreshed_at datetime         null,

    primary key (token),
    foreign key (family) references refresh_token_families (id) on delete cascade on update cascade
);

create table projects
(
    id              int unsigned not null auto_increment,

    title           varchar(50)  not null,
    description     text         null, /* min:10 max:500 check for Cross-Site Scripting! */

    start_date      date         not null, /* actual project's start date */
    target_end_date date         not null, /* actual project's target end date (project must be done on this date) */

    status          tinyint      not null, /* mapped to enum in java */
    /* 1=CREATED, 2=SYSTEM-STARTED, 3=FINISHED, 4=CANCELED, 5=BLOCKED-BY-MODERATOR */

    created_at      datetime     not null,
    started_at      datetime     null, /* recorded start datetime in taskdoni system (different from start_date) */
    canceled_at     datetime     null,
    finished_at     datetime     null,

    primary key (id)
);

/* many-to-many relationship between users and projects! */
create table projects_users
(
    project              int unsigned not null,
    user                 int unsigned not null,

    system_role          tinyint      not null, /* 1=OWNER, 2=MANAGER, 3=COLLABORATOR (map to enum in java) */
    /* only owner can invite user to project! and assign task to both manager and collaborator */
    /* manager can create and assign task to only collaborator */
    /* collaborator only can accept task and manage their tasks! and can assign task to itself! */
    /* each user can also assign task to itself (self assigned tasks) */
    /* all users can see all tasks and other details of project */

    deny_task_assignment bit(1)       not null default 0, /* only OWNER can change this */
    /* don't let this user assign task whether to itself or others */
    /* this field only relate to managers, collaborators not owners! owners always can assign tasks */

    actual_role          varchar(35)  not null, /* role of user in project! ex: Java Back-End Developer (only OWNER can change this) */

    joined_at            datetime     not null,

    primary key (project, user),

    foreign key (project) references projects (id) on delete cascade on update cascade,
    foreign key (user) references users (id) on delete cascade on update cascade
);

create table tasks
(
    id                bigint       not null auto_increment, /* mapped to long in java */
    project           int unsigned not null,

    assigned_by       int unsigned null, /* NOT-OPTIONAL - user-id - a user(manager/owner/collaborator) of project */
    assigned_to       int unsigned null, /* NOT-OPTIONAL - user-id - a user(manager/owner/collaborator) of project */
    /* each user can also assign task to itself (self assigned tasks) */
    /* if a user leave project this two fields must set to null and
       that user is not trackable by other users of same project anymore */
    recorded_name_one varchar(35)  null, /* fill after assigned_by user leave the project [a name of a user] */
    recorded_name_two varchar(35)  null, /* fill after assigned_to user leave the project [a name of a user] */

    title             varchar(50)  not null,
    description       text         null, /* min:5  max:500  check for Cross-Site Scripting! */
    importance        tinyint      not null, /* mapped to enum in java */
    /* 1=SLIGHTLY_IMPORTANT, 2=IMPORTANT, 3=FAIRLY_IMPORTANT, 4=VERY_IMPORTANT */

    must_completed_at datetime     null, /* task deadline */

    status            tinyint      not null, /* map to enum in java! */
    /* 1=ASSIGNED, 2=ACCEPTED, 3=IN_PROGRESS, 4=COMPLETED, 5=VERIFIED, 6=CANCELED, 7=REJECTED */
    /* only assigned_to user can accept,in_progress,complete,reject tasks */
    /* verified by a manager or an owner or assigner_by user */
    /* only managers and owners and assigner of task can verify tasks and also cancel the task */
    /* assigned_to user can't cancel the task */

    /* only owner, manager and assigned_by user can delete tasks */

    reject_reason     tinytext     null, /* reject reason by assigned_to user */
    cancel_reason     tinytext     null,

    assigned_at       datetime     not null,
    accepted_at       datetime     null,
    progressing_at    datetime     null, /* start progressing at */
    completed_at      datetime     null,
    canceled_at       datetime     null,
    rejected_at       datetime     null,
    verified_at       datetime     null,

    primary key (id),
    foreign key (project) references projects (id) on delete cascade on update cascade,
    foreign key (assigned_by) references users (id) on delete set null on update cascade,
    foreign key (assigned_to) references users (id) on delete set null on update cascade
);

/* table: project_events (ex: task_rejection is an event, task_completion, task_verification
   ,task_assignment, task_cancellation, user_has_left_the_project, new_user_has_joined_the_project) */
/* table: project_invitations */
/* table: conversation_messages */
/* table: notifications */