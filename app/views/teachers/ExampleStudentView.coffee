RootView = require 'views/core/RootView'
Campaigns = require 'collections/Campaigns'
Classroom = require 'models/Classroom'
Courses = require 'collections/Courses'
Levels = require 'collections/Levels'
LevelSessions = require 'collections/LevelSessions'
User = require 'models/User'

module.exports = class ExampleStudentView extends RootView
  id: 'example-student-view'
  template: require 'templates/teachers/example-student-view'

  getTitle: -> return @user?.broadName()

  initialize: (options, classroomID, studentID) ->
    # Add Backbone event handler for classroom data sync'd, and start request from db
    @classroom = new Classroom({_id: classroomID})
    @listenToOnce @classroom, 'sync', @onClassroomSync
    @supermodel.trackRequest(@classroom.fetch())

    # Start Request for all courses from db, only need name field
    @courses = new Courses()
    @supermodel.trackRequest(@courses.fetch({data: { project: 'name' }}))

    # Start request for all levels for this classroom from db, only need name and original fields
    @levels = new Levels()
    @supermodel.trackRequest(@levels.fetchForClassroom(classroomID, {data: {project: 'name,original'}}))

    # Start request for user from db
    @user = new User({_id: studentID})
    @supermodel.trackRequest(@user.fetch())

    @levelProgressMap = {}

    super(options)

  onClassroomSync: ->
    # Now that we have the classroom from db, can request all level sessions for this classroom
    @sessions = new LevelSessions()
    @sessions.comparator = 'changed' # Sort level sessions by changed field, ascending
    @listenTo @sessions, 'sync', @onSessionsSync
    @supermodel.trackRequests(@sessions.fetchForAllClassroomMembers(@classroom))

  onSessionsSync: ->
    # Now we have some level sessions, and enough data to calculate last played string
    # This may be called multiple times due to paged server API calls via fetchForAllClassroomMembers
    return if @destroyed # Don't do anything if page was destroyed after db request
    @updateLastPlayedString()
    @updateLevelProgressMap()

    # Rerun template/jade file to display new last played string
    @render()

  updateLastPlayedString: ->
    # Make sure all our data is loaded, @sessions may not even be intialized yet
    return unless @courses.loaded and @levels.loaded and @sessions?.loaded and @user.loaded

    # Use lodash to find the last session for our user, @sessions already sorted by changed date
    session = _.findLast @sessions.models, (s) => s.get('creator') is @user.id
    return unless session

    # Find course for this level session, for it's name
    # Level.original is the original id, used for level versioning, and connects levels to level sessions
    for versionedCourse in @classroom.get('courses') ? []
      for level in versionedCourse.levels
        if level.original is session.get('level').original
          # Found the level for our level session in the classroom versioned courses
          # Find the full course so we can get it's name
          course = _.find @courses.models, (c) => c.id is versionedCourse._id
          break

    # Find level for this level session, for it's name
    level = @levels.findWhere({original: session.get('level').original})

    # Update last played string based on what we found
    @lastPlayedString = ""
    @lastPlayedString += course.get('name') if course
    @lastPlayedString += ", " if course and level
    @lastPlayedString += level.get('name') if level
    @lastPlayedString += ", " if @lastPlayedString
    @lastPlayedString += session.get('changed')

  updateLevelProgressMap: ->
    return unless @courses.loaded and @levels.loaded and @sessions?.loaded and @user.loaded

    # Map levels to sessions once, so we don't have to search entire session list multiple times below
    levelSessionMap = {}
    for session in @sessions.models
      levelSessionMap[session.get('level').original] = session

    # Create mapping of level to student progress
    @levelProgressMap = {}
    for versionedCourse in @classroom.get('courses') ? []
      for versionedLevel in versionedCourse.levels
        session = levelSessionMap[versionedLevel.original]
        if session
          if session.get('state')?.complete
            @levelProgressMap[versionedLevel.original] = 'complete'
          else
            @levelProgressMap[versionedLevel.original] = 'started'
        else
          @levelProgressMap[versionedLevel.original] = 'not started'
